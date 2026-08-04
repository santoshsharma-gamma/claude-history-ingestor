package com.claude.ingestor.analytics;

/**
 * Tunable weights for {@link EngineeringScoreCalculator}. See that class's
 * Javadoc before treating the resulting score as meaningful in itself -
 * these weights are a starting point to adjust, not a validated formula.
 */
public record EngineeringScoreWeights(
        double perPrompt,
        double perDistinctRepo,
        double perDistinctTechnology,
        double errorRatePenalty
) {
}