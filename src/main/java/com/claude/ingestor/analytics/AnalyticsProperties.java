package com.claude.ingestor.analytics;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * {@code timezone} determines the day boundary for every "today's ..."
 * metric - this matters more than it might seem: the same instant can
 * fall on different calendar dates depending on zone (e.g. 23:30 UTC is
 * already the next day in Tokyo), so picking the right zone for where
 * the person actually works changes which day an event gets counted
 * toward. Defaults live in application.yml, not {@code @DefaultValue}
 * (see Phase 3's note on that annotation and non-trivial defaults).
 */
@ConfigurationProperties(prefix = "claude.analytics")
public record AnalyticsProperties(
        String timezone,
        EngineeringScoreWeights scoreWeights
) {
}