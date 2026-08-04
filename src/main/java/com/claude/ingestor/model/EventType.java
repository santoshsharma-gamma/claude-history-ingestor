package com.claude.ingestor.model;

/**
 * The {@code type} field of a raw Claude Code history record.
 *
 * {@link #UNKNOWN} is the deliberate fallback for anything not recognized
 * (including a missing or null {@code type}) rather than throwing - this
 * schema isn't officially published, so a future Claude Code version could
 * introduce a new record type at any time, and this project would rather
 * degrade gracefully (tag it UNKNOWN, keep the raw line around) than crash
 * or drop data.
 */
public enum EventType {
    USER,
    ASSISTANT,
    SUMMARY,
    UNKNOWN;

    public static EventType fromRaw(String raw) {
        if (raw == null) {
            return UNKNOWN;
        }
        return switch (raw) {
            case "user" -> USER;
            case "assistant" -> ASSISTANT;
            case "summary" -> SUMMARY;
            default -> UNKNOWN;
        };
    }
}