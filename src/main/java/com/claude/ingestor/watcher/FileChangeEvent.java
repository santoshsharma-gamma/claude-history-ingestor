package com.claude.ingestor.watcher;

import java.nio.file.Path;
import java.time.Instant;

/**
 * Published via {@link org.springframework.context.ApplicationEventPublisher}
 * whenever the watcher notices a matching file appear, change, or disappear.
 *
 * Deliberately contains no file content — later phases subscribe with
 * {@code @EventListener(FileChangeEvent.class)} and decide what to do
 * (Phase 3 tracks read offsets, Phase 4 actually parses new lines).
 */
public record FileChangeEvent(
        Path filePath,
        String projectName,
        FileChangeKind kind,
        Instant detectedAt
) {
}
