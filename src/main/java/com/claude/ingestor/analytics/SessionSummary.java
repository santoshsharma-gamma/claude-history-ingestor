package com.claude.ingestor.analytics;

import java.time.Instant;

public record SessionSummary(
        String sessionId,
        String repoName,
        Instant firstEventAt,
        Instant lastEventAt,
        long durationSeconds,
        long promptCount,
        double costUsd
) {
}