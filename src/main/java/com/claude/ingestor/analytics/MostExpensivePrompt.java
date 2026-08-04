package com.claude.ingestor.analytics;

import java.time.Instant;

/**
 * The costliest single event seen so far (all-time, not just today). In
 * practice this is always an {@code ASSISTANT}-type event, since token
 * usage - and therefore cost - only ever appears on assistant messages in
 * Claude Code's schema. "Prompt" here follows the roadmap's own naming,
 * but {@code responseSnippet} is genuinely the assistant's response text,
 * not the user's prompt that triggered it - the two aren't in the same
 * record in this schema, so this captures what's actually available.
 */
public record MostExpensivePrompt(
        String sessionId,
        String repoName,
        String model,
        double costUsd,
        Instant timestamp,
        String responseSnippet
) {
}