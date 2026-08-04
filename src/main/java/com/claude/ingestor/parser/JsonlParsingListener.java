package com.claude.ingestor.parser;

import com.claude.ingestor.offset.NewContentAvailableEvent;
import com.claude.ingestor.offset.OffsetStore;
import com.claude.ingestor.util.Json;
import java.io.IOException;
import java.time.Clock;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Consumes Phase 3's {@link NewContentAvailableEvent}, reads exactly that
 * byte range via {@link JsonlLineReader}, parses each complete line as
 * JSON, and publishes {@link ParsedLine} or {@link LineParseFailure} per
 * line.
 *
 * This is also where the offset-commit gap flagged in Phase 3 gets
 * closed: {@code OffsetTrackingListener} no longer calls
 * {@code advanceOffset} itself (see its Javadoc) - this class does, using
 * {@link LineReadResult#consumedUpToOffset()}, which only ever reflects
 * complete lines actually read. A line that's mid-write when the range is
 * read simply isn't consumed yet; it'll show up again (fully written)
 * the next time a MODIFIED event fires for that file.
 */
@Component
public class JsonlParsingListener {

    private static final Logger log = LoggerFactory.getLogger(JsonlParsingListener.class);

    private final JsonlLineReader lineReader;
    private final OffsetStore offsetStore;
    private final ApplicationEventPublisher publisher;
    private final ParserProperties properties;
    private final Clock clock;

    public JsonlParsingListener(JsonlLineReader lineReader,
                                OffsetStore offsetStore,
                                ApplicationEventPublisher publisher,
                                ParserProperties properties,
                                Clock clock) {
        this.lineReader = lineReader;
        this.offsetStore = offsetStore;
        this.publisher = publisher;
        this.properties = properties;
        this.clock = clock;
    }

    @EventListener
    public void onNewContent(NewContentAvailableEvent event) {
        try {
            LineReadResult result = lineReader.readRange(
                    event.filePath(), event.fromOffset(), event.toOffset(),
                    (line, start, end) -> parseAndPublish(event, line, start, end));

            offsetStore.advanceOffset(event.filePath(), result.consumedUpToOffset());

            if (result.hadTrailingPartialBytes()) {
                log.debug("'{}' had a trailing partial line at offset {} - left for next read",
                        event.filePath(), result.consumedUpToOffset());
            }
            log.debug("Parsed {} line(s) from '{}', committed offset {}",
                    result.linesEmitted(), event.filePath(), result.consumedUpToOffset());
        } catch (IOException e) {
            // Deliberately does NOT advance the offset here - if we couldn't
            // read the range at all, the next event for this file will retry
            // from the same (still-uncommitted) starting point.
            log.error("Failed to read '{}' range [{}, {}): {}",
                    event.filePath(), event.fromOffset(), event.toOffset(), e.getMessage(), e);
        }
    }

    private void parseAndPublish(NewContentAvailableEvent event, String line, long start, long end) {
        String trimmed = line.trim();
        if (trimmed.isEmpty()) {
            return;
        }

        try {
            Object json = Json.parse(trimmed);
            publisher.publishEvent(new ParsedLine(
                    event.filePath(), event.projectName(), json, line, start, end, Instant.now(clock)));
        } catch (Json.JsonParseException e) {
            String truncated = line.length() > properties.maxRawLineLengthLogged()
                    ? line.substring(0, properties.maxRawLineLengthLogged()) + "...(truncated)"
                    : line;
            log.warn("Failed to parse line in '{}' at [{}, {}): {}", event.filePath(), start, end, e.getMessage());
            publisher.publishEvent(new LineParseFailure(
                    event.filePath(), event.projectName(), truncated, e.getMessage(), start, end, Instant.now(clock)));
        }
    }
}
