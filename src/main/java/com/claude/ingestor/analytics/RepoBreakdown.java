package com.claude.ingestor.analytics;

import java.time.Instant;
import java.util.Set;

/** All-time activity for one repository, for {@code GET /analytics/repositories}. */
public record RepoBreakdown(
        String repoName,
        long eventCount,
        long promptCount,
        double costUsd,
        Instant lastActiveAt,
        Set<String> technologies
) {
}