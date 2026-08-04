package com.claude.ingestor.model;

public record TokenUsage(
        long inputTokens,
        long outputTokens,
        long cacheReadInputTokens,
        long cacheCreationInputTokens
) {
    public static final TokenUsage EMPTY = new TokenUsage(0, 0, 0, 0);
}
