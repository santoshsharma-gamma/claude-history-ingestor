package com.claude.ingestor.sender;

import com.claude.ingestor.analytics.CostCalculator;
import com.claude.ingestor.analytics.PromptClassifier;
import com.claude.ingestor.model.ClaudeEvent;
import com.claude.ingestor.model.ContentBlock;
import com.claude.ingestor.model.EventType;
import com.claude.ingestor.model.TextBlock;
import com.claude.ingestor.model.ToolResultBlock;
import com.claude.ingestor.model.ToolUseBlock;
import com.claude.ingestor.repository.RepositoryEnrichment;
import com.claude.ingestor.util.Json;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

/**
 * Maps one {@link ClaudeEvent} (plus its {@link RepositoryEnrichment}
 * from Phase 7) to an OTLP {@code LogRecord} JSON fragment (the object
 * that goes inside {@code resourceLogs[].scopeLogs[].logRecords[]}).
 *
 * Deliberately builds JSON by hand with {@link Json#quote} rather than via
 * Jackson (see {@code util.Json}'s Javadoc for why) or via
 * {@code RestClient}'s automatic object serialization - this keeps the
 * exact wire shape fully under this project's control and testable
 * without a Jackson version dependency.
 *
 * This is essentially the same mapping the standalone OTEL ingester tool
 * (built earlier in this conversation) did over raw JSON - but working
 * from the typed {@link ClaudeEvent} model instead of defensive
 * {@code Map} lookups, since Phase 5 already did that normalization.
 *
 * As of Phase 10, also depends on Phase 8's {@link CostCalculator} to
 * attach an {@code llm.cost_usd} attribute - without it, there was no
 * cost figure at all in the exported OTLP stream, making a "cost over
 * time" OpenObserve dashboard panel impossible even though the app's own
 * REST API (Phase 9) could already answer that question internally.
 *
 * Also attaches {@code event.is_prompt} using Phase 8's
 * {@link PromptClassifier} - same reasoning as cost: without this, there
 * was no way to distinguish an actual typed user message from an
 * automatic {@code tool_result} being fed back, in SQL against the
 * exported stream, even though the app's own analytics engine already
 * drew that distinction internally for its "today's prompts" metric.
 *
 * Also attaches {@code code.jira_ticket}, extracted from
 * {@code gitBranch} via {@link #JIRA_TICKET_PATTERN} - lets a dashboard
 * group activity by ticket without re-deriving this in every query. The
 * pattern assumes a fairly standard JIRA key shape (uppercase letters,
 * optionally with digits, then a hyphen, then digits - e.g.
 * {@code GGLOBDRA-1813}); adjust it if your project keys look different.
 */
@Component
public class ClaudeEventToLogRecordMapper {

    private static final Pattern JIRA_TICKET_PATTERN = Pattern.compile("([A-Z][A-Z0-9]+-\\d+)");

    private final CostCalculator costCalculator;

    public ClaudeEventToLogRecordMapper(CostCalculator costCalculator) {
        this.costCalculator = costCalculator;
    }

    public String toLogRecordJson(ClaudeEvent event, RepositoryEnrichment enrichment) {
        StringBuilder sb = new StringBuilder();

        long epochNanos = event.timestamp().getEpochSecond() * 1_000_000_000L + event.timestamp().getNano();
        sb.append('{');
        sb.append("\"timeUnixNano\":\"").append(epochNanos).append("\",");

        boolean isError = event.toolUseResult() != null && event.toolUseResult().isError();
        String toolName = null;
        String bodyText;

        if (event.type() == EventType.SUMMARY) {
            bodyText = event.summary();
        } else if (event.message() != null) {
            StringBuilder body = new StringBuilder();
            for (ContentBlock block : event.message().content()) {
                if (block instanceof TextBlock tb) {
                    appendWithNewline(body, tb.text());
                } else if (block instanceof ToolUseBlock tu) {
                    appendWithNewline(body, "[tool_use: " + tu.name() + "]");
                    if (toolName == null) {
                        toolName = tu.name();
                    }
                } else if (block instanceof ToolResultBlock tr) {
                    appendWithNewline(body, tr.content());
                    if (tr.isError()) {
                        isError = true;
                    }
                }
                // UnknownBlock contributes nothing to body text, but nothing is
                // lost - event.rawLine() (attached below) still has it in full.
            }
            bodyText = body.length() > 0 ? body.toString() : null;
        } else {
            bodyText = null;
        }

        int severityNumber = isError ? 17 : (event.type() == EventType.SUMMARY ? 5 : 9);
        String severityText = isError ? "ERROR" : (event.type() == EventType.SUMMARY ? "DEBUG" : "INFO");

        sb.append("\"severityNumber\":").append(severityNumber).append(',');
        sb.append("\"severityText\":").append(Json.quote(severityText)).append(',');
        sb.append("\"body\":{\"stringValue\":").append(Json.quote(bodyText)).append('}');

        sb.append(",\"attributes\":[");
        boolean[] first = {true};

        putStringAttr(sb, first, "event.type", event.type().name());
        putStringAttr(sb, first, "session.id", event.sessionId());
        putStringAttr(sb, first, "event.uuid", event.uuid());
        putStringAttr(sb, first, "event.parent_uuid", event.parentUuid());
        putStringAttr(sb, first, "event.request_id", event.requestId());
        putStringAttr(sb, first, "event.leaf_uuid", event.leafUuid());
        putStringAttr(sb, first, "user.type", event.userType());
        putStringAttr(sb, first, "code.cwd", event.cwd());
        putStringAttr(sb, first, "code.git_branch", event.gitBranch());
        putStringAttr(sb, first, "code.jira_ticket", extractJiraTicket(event.gitBranch()));
        putStringAttr(sb, first, "code.version", event.version());
        putBoolAttr(sb, first, "event.is_sidechain", event.isSidechain());
        putBoolAttr(sb, first, "event.is_error", isError);
        putBoolAttr(sb, first, "event.is_prompt", PromptClassifier.isPrompt(event));

        if (event.message() != null) {
            putStringAttr(sb, first, "llm.model", event.message().model());
            putStringAttr(sb, first, "tool.name", toolName);
            if (event.message().usage() != null) {
                putLongAttr(sb, first, "llm.usage.input_tokens", event.message().usage().inputTokens());
                putLongAttr(sb, first, "llm.usage.output_tokens", event.message().usage().outputTokens());
                putLongAttr(sb, first, "llm.usage.cache_read_input_tokens", event.message().usage().cacheReadInputTokens());
                putLongAttr(sb, first, "llm.usage.cache_creation_input_tokens", event.message().usage().cacheCreationInputTokens());
            }
            double cost = costCalculator.costOf(event.message().model(), event.message().usage());
            if (cost > 0 && Double.isFinite(cost)) {
                // Sent as a string, not a bare JSON number (doubleValue) -
                // confirmed via actual payload analysis (not a guess) that
                // OpenObserve's OTLP parser breaks exactly at the boundary
                // right after a raw doubleValue token. Every other
                // numeric-looking attribute in this payload (token counts,
                // byte offsets) is already a quoted string and works fine;
                // this makes cost consistent with those rather than the
                // only differently-shaped value in the whole structure.
                // Query it in SQL with e.g. CAST(llm_cost_usd AS DOUBLE).
                putStringAttr(sb, first, "llm.cost_usd", String.valueOf(cost));
            }
        }

        putStringAttr(sb, first, "source.file", event.sourceFile() != null ? event.sourceFile().toString() : null);
        putStringAttr(sb, first, "project.name", event.projectName());
        putLongAttr(sb, first, "source.line_start_offset", event.lineStartOffset());
        putLongAttr(sb, first, "source.line_end_offset", event.lineEndOffset());
        putStringAttr(sb, first, "event.raw", event.rawLine());

        if (enrichment != null) {
            putStringAttr(sb, first, "repo.name", enrichment.repoName());
            if (!enrichment.technologies().isEmpty()) {
                // A stringified JSON array (e.g. ["Java (Maven)","Terraform"]),
                // not comma-joined - OpenObserve's array functions
                // (cast_to_arr + unnest) only operate on this shape, which
                // matters for a "top languages" dashboard panel. Comma-joining
                // was a known simplification flagged in Phase 7; this is the
                // "concrete query that needs it" moment that prompted fixing it.
                putStringAttr(sb, first, "repo.technologies", toJsonArray(enrichment.technologies()));
            }
        }

        sb.append(']');
        sb.append('}');
        return sb.toString();
    }

    private static void appendWithNewline(StringBuilder body, String text) {
        if (text == null) {
            return;
        }
        if (body.length() > 0) {
            body.append('\n');
        }
        body.append(text);
    }

    /**
     * Pulls a JIRA-style ticket key (e.g. {@code GGLOBDRA-1813}) out of a
     * git branch name like {@code feature/GGLOBDRA-1813-provisioning-s3-bucket}.
     * Returns null if nothing matching {@link #JIRA_TICKET_PATTERN} is
     * found - a version string like {@code release/2.1.220} or a plain
     * branch name like {@code main} correctly yields null, not a false match.
     */
    private static String extractJiraTicket(String gitBranch) {
        if (gitBranch == null) {
            return null;
        }
        Matcher matcher = JIRA_TICKET_PATTERN.matcher(gitBranch);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static void putStringAttr(StringBuilder sb, boolean[] first, String key, String value) {
        if (value == null) {
            return;
        }
        if (!first[0]) {
            sb.append(',');
        }
        first[0] = false;
        sb.append("{\"key\":").append(Json.quote(key))
                .append(",\"value\":{\"stringValue\":").append(Json.quote(value)).append("}}");
    }

    private static void putBoolAttr(StringBuilder sb, boolean[] first, String key, boolean value) {
        if (!first[0]) {
            sb.append(',');
        }
        first[0] = false;
        sb.append("{\"key\":").append(Json.quote(key))
                .append(",\"value\":{\"boolValue\":").append(value).append("}}");
    }

    private static void putLongAttr(StringBuilder sb, boolean[] first, String key, long value) {
        if (!first[0]) {
            sb.append(',');
        }
        first[0] = false;
        sb.append("{\"key\":").append(Json.quote(key))
                .append(",\"value\":{\"intValue\":\"").append(value).append("\"}}");
    }

    /** Renders {@code values} as a stringified JSON array, e.g. {@code ["Java (Maven)","Terraform"]}. */
    private static String toJsonArray(Set<String> values) {
        StringBuilder arr = new StringBuilder("[");
        boolean first = true;
        for (String value : values) {
            if (!first) {
                arr.append(',');
            }
            first = false;
            arr.append(Json.quote(value));
        }
        arr.append(']');
        return arr.toString();
    }
}
