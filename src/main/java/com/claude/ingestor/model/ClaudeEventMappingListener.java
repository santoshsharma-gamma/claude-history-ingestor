package com.claude.ingestor.model;

import com.claude.ingestor.parser.ParsedLine;
import java.time.Clock;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Bridges Phase 4's {@link ParsedLine} (generic JSON tree, no domain
 * meaning yet) to {@link ClaudeEvent} (the typed domain model). Later
 * phases - enrichment, analytics, the OpenObserve sender - subscribe to
 * {@code ClaudeEvent} rather than {@code ParsedLine}, so they never touch
 * a raw JSON tree directly.
 */
@Component
public class ClaudeEventMappingListener {

    private static final Logger log = LoggerFactory.getLogger(ClaudeEventMappingListener.class);

    private final ClaudeEventMapper mapper;
    private final ApplicationEventPublisher publisher;
    private final Clock clock;

    public ClaudeEventMappingListener(ClaudeEventMapper mapper, ApplicationEventPublisher publisher, Clock clock) {
        this.mapper = mapper;
        this.publisher = publisher;
        this.clock = clock;
    }

    @EventListener
    public void onParsedLine(ParsedLine line) {
        Instant fallbackTimestamp = line.parsedAt() != null ? line.parsedAt() : Instant.now(clock);

        ClaudeEvent event = mapper.map(
                line.filePath(),
                line.projectName(),
                line.json(),
                line.rawLine(),
                line.lineStartOffset(),
                line.lineEndOffset(),
                fallbackTimestamp
        );

        if (event.type() == EventType.UNKNOWN) {
            log.debug("Mapped an UNKNOWN-type event from '{}' at [{}, {}) - raw line preserved for inspection",
                    line.filePath(), line.lineStartOffset(), line.lineEndOffset());
        } else {
            log.debug("Mapped {} event from '{}' (session {})", event.type(), line.filePath(), event.sessionId());
        }

        publisher.publishEvent(event);
    }
}
