package com.claude.ingestor.analytics;

/**
 * All-time highlights (not day-scoped, unlike {@link DailyMetrics}), for
 * {@code GET /analytics/activity}.
 */
public record ActivityHighlights(
        String mostActiveRepo,
        SessionSummary longestSession,
        MostExpensivePrompt mostExpensivePrompt,
        String topTechnology
) {
}