package com.claude.ingestor.analytics;

import com.claude.ingestor.model.TokenUsage;
import org.springframework.stereotype.Component;

/**
 * Estimates USD cost from a message's {@link TokenUsage} and model name,
 * using {@link PricingProperties}.
 *
 * Cache pricing is approximated rather than exact: Anthropic prices
 * cache-read tokens at 0.1x the base input rate and 5-minute cache writes
 * at 1.25x (1-hour cache writes are 2x, but Claude Code transcripts don't
 * record which cache TTL was used, so this assumes the more common
 * 5-minute default). Close enough for a "roughly how much am I spending"
 * dashboard; not a substitute for Anthropic's own billing.
 */
@Component
public class CostCalculator {

    private static final double CACHE_READ_MULTIPLIER = 0.1;
    private static final double CACHE_WRITE_MULTIPLIER = 1.25;

    private final PricingProperties properties;

    public CostCalculator(PricingProperties properties) {
        this.properties = properties;
    }

    public double costOf(String model, TokenUsage usage) {
        if (usage == null) {
            return 0.0;
        }
        ModelPrice price = resolvePrice(model);

        double inputCost = usage.inputTokens() / 1_000_000.0 * price.inputPerMillion();
        double outputCost = usage.outputTokens() / 1_000_000.0 * price.outputPerMillion();
        double cacheReadCost = usage.cacheReadInputTokens() / 1_000_000.0 * (price.inputPerMillion() * CACHE_READ_MULTIPLIER);
        double cacheWriteCost = usage.cacheCreationInputTokens() / 1_000_000.0 * (price.inputPerMillion() * CACHE_WRITE_MULTIPLIER);

        return inputCost + outputCost + cacheReadCost + cacheWriteCost;
    }

    private ModelPrice resolvePrice(String model) {
        if (model == null || !properties.models().containsKey(model)) {
            return properties.defaultPrice();
        }
        return properties.models().get(model);
    }
}
