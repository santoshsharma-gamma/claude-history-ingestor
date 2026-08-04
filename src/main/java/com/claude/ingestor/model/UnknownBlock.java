package com.claude.ingestor.model;
/**
 * A content block whose {@code type} isn't one this project recognizes
 * (yet). Keeps the raw parsed block around in full so nothing is silently
 * dropped if a future Claude Code version introduces a new block type.
 */
public record UnknownBlock(String rawType, Object raw) implements ContentBlock {
}
