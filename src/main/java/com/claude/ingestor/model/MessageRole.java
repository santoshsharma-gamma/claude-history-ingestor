package com.claude.ingestor.model;

/** The {@code role} field of a message. See {@link EventType} for why UNKNOWN exists. */
public enum MessageRole {
    USER,
    ASSISTANT,
    UNKNOWN;

    public static MessageRole fromRaw(String raw) {
        if (raw == null) {
            return UNKNOWN;
        }
        return switch (raw) {
            case "user" -> USER;
            case "assistant" -> ASSISTANT;
            default -> UNKNOWN;
        };
    }
}
