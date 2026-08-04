package com.claude.ingestor.model;

import java.nio.file.Path;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Converts a {@code ParsedLine}'s generic JSON tree
 * ({@code Map}/{@code List}/{@code String}/{@code Long}/{@code Double}/
 * {@code Boolean}/{@code null}, exactly what {@code util.Json.parse}
 * produces) into a {@link ClaudeEvent}.
 *
 * Never throws. Claude Code's history schema isn't officially published,
 * so this reads defensively at every level - an unrecognized {@code type},
 * a missing field, a block shape that doesn't match anything known, or
 * even a line whose top-level JSON isn't an object at all, all degrade to
 * a best-effort {@code ClaudeEvent} (tagged {@link EventType#UNKNOWN}
 * where relevant) rather than being dropped or crashing the pipeline.
 * {@code rawLine} is always preserved so nothing is silently lost even
 * when a shape isn't recognized.
 */
@Component
public class ClaudeEventMapper {

    public ClaudeEvent map(Path sourceFile, String projectName, Object json, String rawLine,
                           long lineStartOffset, long lineEndOffset, Instant fallbackTimestamp) {

        Map<String, Object> record = asMap(json);
        if (record == null) {
            // Not even a JSON object at the top level - keep the raw line,
            // tag it UNKNOWN, and move on rather than throwing.
            return new ClaudeEvent(EventType.UNKNOWN, null, null, null, null, null, false,
                    null, null, null, fallbackTimestamp, null, null, null, null,
                    sourceFile, projectName, lineStartOffset, lineEndOffset, rawLine);
        }

        EventType type = EventType.fromRaw(asString(record.get("type")));
        Message message = mapMessage(asMap(record.get("message")));
        ToolUseResult toolUseResult = mapToolUseResult(asMap(record.get("toolUseResult")));
        Instant timestamp = resolveInstant(asString(record.get("timestamp")), fallbackTimestamp);

        return new ClaudeEvent(
                type,
                asString(record.get("sessionId")),
                asString(record.get("uuid")),
                asString(record.get("parentUuid")),
                asString(record.get("requestId")),
                asString(record.get("userType")),
                Boolean.TRUE.equals(record.get("isSidechain")),
                asString(record.get("cwd")),
                asString(record.get("gitBranch")),
                asString(record.get("version")),
                timestamp,
                message,
                asString(record.get("summary")),
                asString(record.get("leafUuid")),
                toolUseResult,
                sourceFile,
                projectName,
                lineStartOffset,
                lineEndOffset,
                rawLine
        );
    }

    private Message mapMessage(Map<String, Object> raw) {
        if (raw == null) {
            return null;
        }
        MessageRole role = MessageRole.fromRaw(asString(raw.get("role")));
        String model = asString(raw.get("model"));
        List<ContentBlock> content = mapContent(raw.get("content"));
        TokenUsage usage = mapUsage(asMap(raw.get("usage")));
        return new Message(role, model, content, usage);
    }

    private List<ContentBlock> mapContent(Object rawContent) {
        List<ContentBlock> blocks = new ArrayList<>();

        if (rawContent instanceof String text) {
            blocks.add(new TextBlock(text));
            return blocks;
        }

        if (rawContent instanceof List<?> list) {
            for (Object item : list) {
                Map<String, Object> block = asMap(item);
                if (block == null) {
                    continue;
                }
                String blockType = asString(block.get("type"));
                if ("text".equals(blockType)) {
                    blocks.add(new TextBlock(asString(block.get("text"))));
                } else if ("tool_use".equals(blockType)) {
                    blocks.add(new ToolUseBlock(asString(block.get("name")), block.get("input")));
                } else if ("tool_result".equals(blockType)) {
                    Object inner = block.get("content");
                    String text = (inner instanceof String s) ? s : String.valueOf(inner);
                    boolean isError = Boolean.TRUE.equals(block.get("is_error"));
                    blocks.add(new ToolResultBlock(text, isError));
                } else {
                    blocks.add(new UnknownBlock(blockType, block));
                }
            }
        }
        // If rawContent is neither a String nor a List (e.g. missing, or an
        // unexpected type), blocks stays empty rather than throwing.

        return blocks;
    }

    private TokenUsage mapUsage(Map<String, Object> raw) {
        if (raw == null) {
            return TokenUsage.EMPTY;
        }
        return new TokenUsage(
                asLong(raw.get("input_tokens")),
                asLong(raw.get("output_tokens")),
                asLong(raw.get("cache_read_input_tokens")),
                asLong(raw.get("cache_creation_input_tokens"))
        );
    }

    private ToolUseResult mapToolUseResult(Map<String, Object> raw) {
        if (raw == null) {
            return null;
        }
        return new ToolUseResult(Boolean.TRUE.equals(raw.get("is_error")), raw);
    }

    private Instant resolveInstant(String s, Instant fallback) {
        if (s == null) {
            return fallback;
        }
        try {
            return Instant.parse(s);
        } catch (DateTimeParseException e) {
            return fallback;
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object o) {
        return (o instanceof Map) ? (Map<String, Object>) o : null;
    }

    private static String asString(Object o) {
        return (o instanceof String) ? (String) o : null;
    }

    private static long asLong(Object o) {
        if (o instanceof Long l) {
            return l;
        }
        if (o instanceof Integer i) {
            return i;
        }
        if (o instanceof Double d) {
            return d.longValue();
        }
        return 0L;
    }
}