package com.claude.ingestor.analytics;

import java.time.LocalDate;

/**
 * Today's day-scoped metrics (see {@link ActivityHighlights} for the
 * all-time counterparts), for {@code GET /analytics/daily}.
 */
public record DailyMetrics(
        LocalDate date,
        long promptsToday,
        double costTodayUsd,
        int sessionsToday,
        double engineeringScore
) {
}