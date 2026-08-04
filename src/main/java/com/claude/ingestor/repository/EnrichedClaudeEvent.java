package com.claude.ingestor.repository;

import com.claude.ingestor.model.ClaudeEvent;

/**
 * Published by {@link EnrichmentListener} for every {@link ClaudeEvent}.
 * Later phases (analytics, the OpenObserve sender) subscribe to this
 * instead of the bare {@code ClaudeEvent} once they want repo/technology
 * context alongside it.
 */
public record EnrichedClaudeEvent(
        ClaudeEvent event,
        RepositoryEnrichment enrichment
) {
}