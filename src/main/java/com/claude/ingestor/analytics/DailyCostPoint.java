package com.claude.ingestor.analytics;

import java.time.LocalDate;

/**
 * One day's point in a cost trend. Days with no recorded activity appear
 * with zeroed values rather than being omitted, so a chart built from a
 * list of these doesn't need its own gap-filling logic.
 */
public record DailyCostPoint(
        LocalDate date,
        double costUsd,
        long promptCount,
        int sessionCount
) {
}