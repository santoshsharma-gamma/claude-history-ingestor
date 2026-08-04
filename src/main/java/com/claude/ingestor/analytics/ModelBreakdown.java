package com.claude.ingestor.analytics;

/** All-time usage/cost for one model, for {@code GET /analytics/models}. */
public record ModelBreakdown(
        String model,
        long eventCount,
        long inputTokens,
        long outputTokens,
        double costUsd
) {
}