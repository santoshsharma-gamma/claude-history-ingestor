package com.claude.ingestor.repository;

import java.time.Instant;
import java.util.Set;

/**
 * What {@link RepositoryEnricher} figured out about a project directory.
 *
 * {@code repoName} comes straight from {@code ClaudeEvent.cwd()}'s last
 * path segment - a real filesystem path, not Phase 2's watcher-derived
 * project folder name (which is a dash-encoded form of a path and can't
 * be reliably decoded back: is {@code asset-search} one path segment or
 * two? There's no way to tell after the fact, since the encoding uses
 * the same character to replace path separators as can appear inside a
 * real folder name). Using {@code cwd} sidesteps that ambiguity entirely.
 */
public record RepositoryEnrichment(
        String repoName,
        Set<String> technologies,
        Instant enrichedAt
) {
    public static final RepositoryEnrichment UNKNOWN =
            new RepositoryEnrichment("unknown", Set.of(), Instant.EPOCH);
}