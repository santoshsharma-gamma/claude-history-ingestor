package com.claude.ingestor.analytics;

import java.util.Map;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Per-model pricing, in USD per million tokens, used by {@link CostCalculator}.
 *
 * Defaults live in application.yml (not {@code @DefaultValue} - see the
 * lesson learned in Phase 3 about that annotation and non-trivial
 * defaults) and reflect Anthropic's published rates as of when this was
 * written - {@code claude.pricing} is fully overridable, and pricing does
 * change over time (Claude Sonnet 5's introductory rate, for instance, is
 * only in effect through August 31, 2026 per Anthropic's pricing page -
 * check platform.claude.com/docs/en/about-claude/pricing for current
 * numbers before trusting cost figures this produces for anything that
 * matters).
 */
@ConfigurationProperties(prefix = "claude.pricing")
public record PricingProperties(
        Map<String, ModelPrice> models,
        ModelPrice defaultPrice
) {
}