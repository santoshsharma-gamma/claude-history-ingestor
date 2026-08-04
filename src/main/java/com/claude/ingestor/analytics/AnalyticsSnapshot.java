package com.claude.ingestor.analytics;

import java.time.LocalDate;

/**
 * What {@link MetricsAccumulator#snapshot()} returns - the read-model
 * Phase 9's REST APIs will expose.
 *
 * {@code promptsToday}/{@code costTodayUsd}/{@code sessionsToday} are
 * scoped to {@code date} (per {@code claude.analytics.timezone}).
 * {@code mostActiveRepo}, {@code longestSession}, {@code mostExpensivePrompt},
 * and {@code topTechnology} are all-time - matching how the roadmap listed
 * them separately from the explicitly "today's ..." metrics.
 * {@code engineeringScore} is computed from today's activity; see
 * {@link EngineeringScoreCalculator}'s Javadoc before reading too much
 * into it.
 */
public record AnalyticsSnapshot(
        LocalDate date,
        long promptsToday,
        double costTodayUsd,
        int sessionsToday,
        String mostActiveRepo,
        SessionSummary longestSession,
        MostExpensivePrompt mostExpensivePrompt,
        String topTechnology,
        double engineeringScore
) {
}