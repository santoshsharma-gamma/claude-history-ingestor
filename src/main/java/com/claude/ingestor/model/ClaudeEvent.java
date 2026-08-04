package com.claude.ingestor.model;

import java.nio.file.Path;
import java.time.Instant;

/**
 * One Claude Code history record, mapped from the generic JSON tree
 * {@code ClaudeEventMapper} receives from Phase 4's {@code ParsedLine}.
 *
 * Everything here is nullable except {@link #type()} and
 * {@link #timestamp()} - the schema is unofficial and records vary a lot
 * by {@code type} (a {@code SUMMARY} record has no {@code message}, most
 * records have no {@code summary}, etc). Consumers should branch on
 * {@link #type()} before assuming a field is present.
 *
 * {@code sourceFile}/{@code projectName}/{@code lineStartOffset}/
 * {@code lineEndOffset}/{@code rawLine} are provenance, not part of
 * Claude Code's own schema - carried along so later phases (analytics,
 * the OpenObserve sender) don't need to thread {@code ParsedLine}
 * alongside every {@code ClaudeEvent}.
 */
public record ClaudeEvent(
        EventType type,
        String sessionId,
        String uuid,
        String parentUuid,
        String requestId,
        String userType,
        boolean isSidechain,
        String cwd,
        String gitBranch,
        String version,
        Instant timestamp,
        Message message,
        String summary,
        String leafUuid,
        ToolUseResult toolUseResult,
        Path sourceFile,
        String projectName,
        long lineStartOffset,
        long lineEndOffset,
        String rawLine
) {
}
