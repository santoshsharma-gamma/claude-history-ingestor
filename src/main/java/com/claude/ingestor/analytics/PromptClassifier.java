package com.claude.ingestor.analytics;

import com.claude.ingestor.model.ClaudeEvent;
import com.claude.ingestor.model.ContentBlock;
import com.claude.ingestor.model.EventType;
import com.claude.ingestor.model.TextBlock;

/**
 * Claude Code's schema has no explicit "this is a prompt" flag - a
 * {@code USER}-type record can be an actual typed message, or just a
 * {@code tool_result} being fed back automatically after a tool call. This
 * class draws that line in exactly one place, so every metric that counts
 * "prompts" agrees on the definition: a {@code USER} event counts as a
 * prompt only if it has at least one non-blank {@link TextBlock} - i.e.
 * something a person actually typed.
 */
public final class PromptClassifier {

    private PromptClassifier() {
    }

    public static boolean isPrompt(ClaudeEvent event) {
        if (event.type() != EventType.USER || event.message() == null) {
            return false;
        }
        for (ContentBlock block : event.message().content()) {
            if (block instanceof TextBlock tb && tb.text() != null && !tb.text().isBlank()) {
                return true;
            }
        }
        return false;
    }
}