package com.claude.ingestor.analytics;

import com.claude.ingestor.repository.EnrichedClaudeEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Bridges Phase 7's {@link EnrichedClaudeEvent} into {@link MetricsAccumulator}.
 * Deliberately thin - all the actual logic lives in the accumulator so it
 * stays independently testable without Spring's event machinery involved.
 */
@Component
public class AnalyticsEventListener {

    private final MetricsAccumulator accumulator;

    public AnalyticsEventListener(MetricsAccumulator accumulator) {
        this.accumulator = accumulator;
    }

    @EventListener
    public void onEnrichedClaudeEvent(EnrichedClaudeEvent event) {
        accumulator.record(event);
    }
}