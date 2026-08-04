package com.claude.ingestor.model;
/**
 * The record-level {@code toolUseResult} field, which is a sibling of
 * {@code message} (not nested inside it) and shows up on some records
 * summarizing a tool call's outcome. Distinct from {@link ToolResultBlock},
 * which lives inside a message's content array - Claude Code's schema has
 * both, and they're not the same thing.
 */
public record ToolUseResult(boolean isError, Object raw) {
}