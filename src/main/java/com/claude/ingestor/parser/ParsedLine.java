package com.claude.ingestor.parser;

import java.nio.file.Path;
import java.time.Instant;

/**
 * A single JSONL line that parsed successfully. {@code json} is whatever
 * {@link com.santosh.claude.util.Json#parse} returned - typically a
 * {@code Map<String,Object>} for a Claude Code history record, but kept as
 * {@code Object} here since this phase is purely about syntax, not the
 * domain shape (that's Phase 5's job: mapping this generic tree into a
 * proper {@code ClaudeEvent}).
 *
 * Published directly as a Spring application event - later phases
 * subscribe with {@code @EventListener(ParsedLine.class)}.
 */
public record ParsedLine(
        Path filePath,
        String projectName,
        Object json,
        String rawLine,
        long lineStartOffset,
        long lineEndOffset,
        Instant parsedAt
) {
}