package com.claude.ingestor.sender;

import com.claude.ingestor.util.Json;
import java.net.InetAddress;
import java.util.List;
import org.springframework.stereotype.Component;

/**
 * Wraps a batch of {@link ClaudeEventToLogRecordMapper}-produced logRecord
 * fragments into the full OTLP {@code resourceLogs} envelope OpenObserve's
 * {@code /v1/logs} endpoint expects.
 */
@Component
public class OtlpPayloadBuilder {

    private final String hostName;

    public OtlpPayloadBuilder() {
        this.hostName = safeHostName();
    }

    public String buildBatch(List<String> logRecordFragments, String serviceName) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"resourceLogs\":[{\"resource\":{\"attributes\":[");
        sb.append("{\"key\":\"service.name\",\"value\":{\"stringValue\":").append(Json.quote(serviceName)).append("}}");
        if (hostName != null) {
            sb.append(",{\"key\":\"host.name\",\"value\":{\"stringValue\":").append(Json.quote(hostName)).append("}}");
        }
        sb.append("]},\"scopeLogs\":[{\"scope\":{\"name\":\"claude-history-ingestor\",\"version\":\"1.0.0\"},\"logRecords\":[");
        for (int i = 0; i < logRecordFragments.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(logRecordFragments.get(i));
        }
        sb.append("]}]}]}");
        return sb.toString();
    }

    private static String safeHostName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return null;
        }
    }
}
