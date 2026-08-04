package com.claude.ingestor.watcher;

import java.nio.file.Path;
import java.time.Instant;

/**
 * A project/repository directory found directly under
 * {@code claude.history-path} — e.g. {@code asset-search},
 * {@code notification}, {@code terraform}, {@code customer-api}.
 */
public record ProjectDirectory(
        String name,
        Path path,
        Instant discoveredAt
) {
}
