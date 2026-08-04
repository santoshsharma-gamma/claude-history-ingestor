package com.claude.ingestor.sender;

import com.claude.ingestor.config.OpenObserveProperties;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * POSTs a batch of OTLP logRecord fragments (already built by
 * {@link ClaudeEventToLogRecordMapper} and wrapped by
 * {@link OtlpPayloadBuilder}) to OpenObserve's
 * {@code /api/{org}/v1/logs} endpoint, using the {@code RestClient} bean
 * Phase 1's {@code RestClientConfig} pre-wired with the base URL and
 * Basic-auth header.
 *
 * Known gap, flagged deliberately rather than hidden: a failed send is
 * logged and the batch is dropped - there's no retry/backoff or
 * dead-letter queue yet. Fine for now; worth revisiting once this runs
 * unattended for real.
 */
@Component
public class OpenObserveSender {

    private static final Logger log = LoggerFactory.getLogger(OpenObserveSender.class);

    private static final String SERVICE_NAME = "claude-history-ingestor";

    private final RestClient restClient;
    private final OtlpPayloadBuilder payloadBuilder;
    private final OpenObserveProperties properties;

    public OpenObserveSender(RestClient openObserveRestClient, OtlpPayloadBuilder payloadBuilder,
                             OpenObserveProperties properties) {
        this.restClient = openObserveRestClient;
        this.payloadBuilder = payloadBuilder;
        this.properties = properties;
    }

    private static final int MAX_PAYLOAD_LOGGED = 10_000;

    /** @return true if OpenObserve accepted the batch (2xx), false otherwise (already logged). */
    public boolean sendBatch(List<String> logRecordFragments) {
        if (logRecordFragments.isEmpty()) {
            return true;
        }

        String payload = payloadBuilder.buildBatch(logRecordFragments, SERVICE_NAME);

        try {
            restClient.post()
                    .uri("/api/{org}/v1/logs", properties.org())
                    .contentType(MediaType.APPLICATION_JSON)
                    .header("stream-name", properties.stream())
                    .body(payload)
                    .retrieve()
                    .toBodilessEntity();
            log.debug("Sent batch of {} event(s) to OpenObserve (org={}, stream={})",
                    logRecordFragments.size(), properties.org(), properties.stream());
            return true;
        } catch (RestClientException e) {
            log.error("Failed to send batch of {} event(s) to OpenObserve: {}",
                    logRecordFragments.size(), e.getMessage());
            // Logging the actual payload that failed - not just the error
            // message - since a malformed-JSON error otherwise gives no way
            // to find which field/value actually caused it without
            // reproducing it live. Capped in length so one huge batch
            // can't flood the logs on every failure.
            String logged = payload.length() > MAX_PAYLOAD_LOGGED
                    ? payload.substring(0, MAX_PAYLOAD_LOGGED) + "...(truncated)"
                    : payload;
            log.error("Failing payload was: {}", logged);
            return false;
        }
    }
}
