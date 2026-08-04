package com.claude.ingestor.repository;

import com.claude.ingestor.model.ClaudeEvent;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Bridges Phase 5's {@link ClaudeEvent} to {@link EnrichedClaudeEvent},
 * running {@link RepositoryEnricher} against the event's {@code cwd}.
 */
@Component
public class EnrichmentListener {

    private final RepositoryEnricher enricher;
    private final ApplicationEventPublisher publisher;

    public EnrichmentListener(RepositoryEnricher enricher, ApplicationEventPublisher publisher) {
        this.enricher = enricher;
        this.publisher = publisher;
    }

    @EventListener
    public void onClaudeEvent(ClaudeEvent event) {
        RepositoryEnrichment enrichment = enricher.enrich(event.cwd());
        publisher.publishEvent(new EnrichedClaudeEvent(event, enrichment));
    }
}