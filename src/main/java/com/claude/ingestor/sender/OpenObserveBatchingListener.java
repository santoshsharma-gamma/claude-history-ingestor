package com.claude.ingestor.sender;

import com.claude.ingestor.config.OpenObserveProperties;
import com.claude.ingestor.repository.EnrichedClaudeEvent;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicInteger;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Subscribes to {@link EnrichedClaudeEvent} (Phase 7's enrichment wrapper
 * around Phase 5's {@code ClaudeEvent}), queues it, and flushes to
 * {@link OpenObserveSender} either when the queue reaches
 * {@code openobserve.batch-size} or on a timer (see
 * {@code openobserve.flush-interval-ms}) - whichever comes first. The
 * timer matters because without it, a slow trickle of events (an idle
 * coding session, say) could sit unshipped indefinitely, never reaching
 * the batch-size threshold.
 *
 * Originally (Phase 6) this subscribed directly to {@code ClaudeEvent};
 * switched to {@code EnrichedClaudeEvent} in Phase 7 so the repo-name and
 * detected-technology attributes it adds actually make it into the
 * exported OTLP events, rather than being computed and then discarded.
 *
 * {@code @Scheduled} requires {@code @EnableScheduling}, added to
 * {@code ClaudeHistoryApplication} in Phase 6.
 */
@Component
public class OpenObserveBatchingListener {

    private static final Logger log = LoggerFactory.getLogger(OpenObserveBatchingListener.class);

    private final ConcurrentLinkedQueue<EnrichedClaudeEvent> pending = new ConcurrentLinkedQueue<>();
    private final AtomicInteger pendingCount = new AtomicInteger(0);

    private final ClaudeEventToLogRecordMapper mapper;
    private final OpenObserveSender sender;
    private final OpenObserveProperties properties;

    public OpenObserveBatchingListener(ClaudeEventToLogRecordMapper mapper, OpenObserveSender sender,
                                       OpenObserveProperties properties) {
        this.mapper = mapper;
        this.sender = sender;
        this.properties = properties;
    }

    @EventListener
    public void onEnrichedClaudeEvent(EnrichedClaudeEvent event) {
        pending.add(event);
        if (pendingCount.incrementAndGet() >= properties.batchSize()) {
            flush();
        }
    }

    @Scheduled(fixedDelayString = "${openobserve.flush-interval-ms:2000}")
    public void scheduledFlush() {
        if (pendingCount.get() > 0) {
            flush();
        }
    }

    private synchronized void flush() {
        List<EnrichedClaudeEvent> batch = drainUpTo(properties.batchSize());
        if (batch.isEmpty()) {
            return;
        }

        List<String> logRecords = new ArrayList<>(batch.size());
        for (EnrichedClaudeEvent event : batch) {
            logRecords.add(mapper.toLogRecordJson(event.event(), event.enrichment()));
        }

        boolean ok = sender.sendBatch(logRecords);
        if (!ok) {
            log.warn("Dropped a batch of {} event(s) after a failed send - see the error above for details. "
                    + "(No retry/dead-letter queue yet - see OpenObserveSender's Javadoc.)", batch.size());
        }
    }

    private List<EnrichedClaudeEvent> drainUpTo(int max) {
        List<EnrichedClaudeEvent> drained = new ArrayList<>(Math.min(max, Math.max(pendingCount.get(), 0)));
        EnrichedClaudeEvent item;
        while (drained.size() < max && (item = pending.poll()) != null) {
            pendingCount.decrementAndGet();
            drained.add(item);
        }
        return drained;
    }
}