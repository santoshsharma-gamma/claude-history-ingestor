package com.claude.ingestor.parser;

/**
 * Outcome of {@link JsonlLineReader#readRange}.
 *
 * {@code consumedUpToOffset} is the number that should actually be
 * committed via {@code OffsetStore.advanceOffset} - it's wherever the last
 * complete line ended, which can be less than the range's requested
 * {@code toOffset} if a trailing partial line was left unconsumed.
 */
public record LineReadResult(
        long consumedUpToOffset,
        int linesEmitted,
        boolean hadTrailingPartialBytes
) {
}
