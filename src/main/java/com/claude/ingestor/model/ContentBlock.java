package com.claude.ingestor.model;

/**
 * One block of a message's content. A raw message's {@code content} field
 * is either a plain string or an array of typed blocks - {@code
 * ClaudeEventMapper} normalizes both into a {@code List<ContentBlock>} so
 * every consumer downstream deals with one shape.
 *
 * Sealed so a {@code switch} over the implementations is exhaustive-checked
 * by the compiler; {@link UnknownBlock} is the deliberate escape hatch for
 * any block {@code type} this project doesn't recognize yet.
 */
public sealed interface ContentBlock
        permits TextBlock, ToolUseBlock, ToolResultBlock, UnknownBlock {
}
