package com.claude.ingestor.offset;

import com.claude.ingestor.watcher.FileChangeEvent;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Bridges Phase 2's raw file-system events to offset-aware ones: for every
 * {@link FileChangeEvent} that means "this file might have new bytes"
 * (DISCOVERED, CREATED, MODIFIED), checks the current file size against
 * the last committed offset and, if there's anything new, publishes a
 * {@link NewContentAvailableEvent} describing the range.
 *
 * For DELETED, simply forgets the file's offset - if a file of the same
 * name reappears later, it's treated as brand new.
 */
@Component
public class OffsetTrackingListener {

    private static final Logger log = LoggerFactory.getLogger(OffsetTrackingListener.class);

    private final OffsetStore offsetStore;
    private final ApplicationEventPublisher publisher;
    private final Clock clock;

    public OffsetTrackingListener(OffsetStore offsetStore, ApplicationEventPublisher publisher, Clock clock) {
        this.offsetStore = offsetStore;
        this.publisher = publisher;
        this.clock = clock;
    }

    @EventListener
    public void onFileChange(FileChangeEvent event) {
        switch (event.kind()) {
            case DISCOVERED, CREATED, MODIFIED -> handlePossibleNewContent(event);
            case DELETED -> handleDeleted(event);
        }
    }

    private void handlePossibleNewContent(FileChangeEvent event) {
        Path file = event.filePath();
        long currentSize;
        try {
            currentSize = Files.size(file);
        } catch (IOException e) {
            // Common and harmless: the file can be deleted/renamed between the
            // watcher noticing it and us stat-ing it (e.g. editors that write
            // via a temp file and rename over the original).
            log.debug("Could not stat '{}' ({}) - skipping this event", file, e.getMessage());
            return;
        }

        long lastOffset = offsetStore.getOffset(file);

        if (currentSize < lastOffset) {
            log.info("'{}' shrank ({} -> {} bytes) - treating as rotated/truncated, reading from 0",
                    file, lastOffset, currentSize);
            lastOffset = 0L;
        }

        if (currentSize <= lastOffset) {
            log.debug("No new bytes for '{}' (offset {} = size {})", file, lastOffset, currentSize);
            return;
        }

        log.debug("New content for '{}': bytes [{}, {})", file, lastOffset, currentSize);
        publisher.publishEvent(new NewContentAvailableEvent(
                file, event.projectName(), lastOffset, currentSize, Instant.now(clock)));

        // Offset advancement moved to Phase 4's JsonlParsingListener as of
        // that phase: it commits only up to the last COMPLETE line it
        // actually parsed (via JsonlLineReader), rather than blindly to
        // file size here. See OffsetStore's Javadoc for why that matters -
        // a MODIFIED event can fire mid-write.
    }

    private void handleDeleted(FileChangeEvent event) {
        log.debug("'{}' deleted - forgetting its offset", event.filePath());
        offsetStore.remove(event.filePath());
    }
}