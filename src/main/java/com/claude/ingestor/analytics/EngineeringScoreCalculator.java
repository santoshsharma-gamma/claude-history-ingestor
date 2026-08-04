package com.claude.ingestor.analytics;

import org.springframework.stereotype.Component;

/**
 * Computes a 0-100 "engineering score" for today's activity.
 *
 * <b>Read this before trusting the number:</b> there is no established,
 * industry-standard definition of an "engineering score" from LLM usage
 * data, and this formula doesn't claim to be one. It's a simple weighted
 * sum - prompts, distinct repos touched, distinct technologies touched,
 * minus an error-rate penalty - clamped to [0, 100]. The weights
 * ({@code claude.analytics.score-weights.*}) are fully configurable
 * specifically because they're meant to be tuned to whatever a given team
 * or person actually values (raw volume? breadth across repos? low error
 * rate?), not treated as a validated formula shipped with this project.
 * Treat this as a starting point for a metric you define for yourself,
 * not a measurement.
 */
@Component
public class EngineeringScoreCalculator {

    private final AnalyticsProperties properties;

    public EngineeringScoreCalculator(AnalyticsProperties properties) {
        this.properties = properties;
    }

    public double compute(long promptsToday, int distinctReposToday, int distinctTechnologiesToday, double errorRateToday) {
        EngineeringScoreWeights w = properties.scoreWeights();

        double raw = promptsToday * w.perPrompt()
                + distinctReposToday * w.perDistinctRepo()
                + distinctTechnologiesToday * w.perDistinctTechnology()
                - errorRateToday * w.errorRatePenalty();

        return Math.max(0.0, Math.min(100.0, raw));
    }
}