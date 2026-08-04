package com.claude.ingestor.parser;

import java.nio.file.Path;
import java.time.Instant;

/**
 * A JSONL line that failed to parse as JSON. Doesn't stop the world - one
 * bad line shouldn't block every subsequent line in the file - it's
 * published so later phases can count/alert on parse-failure rate (there's
 * already a dashboard panel sketched for exactly this: an error-rate
 * chart over {@code event.is_error}-style attributes).
 *
 * {@code rawLine} is truncated to {@link ParserProperties#maxRawLineLengthLogged()}
 * so a single pathological line can't blow up log volume.
 */
public record LineParseFailure(
        Path filePath,
        String projectName,
        String rawLine,
        String errorMessage,
        long lineStartOffset,
        long lineEndOffset,
        Instant failedAt
) {
}
