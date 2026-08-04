package com.claude.ingestor.model;

/**
 * A tool call the assistant made. {@code input} is left as the generic
 * parsed JSON tree (not a typed per-tool shape) since tool inputs vary
 * completely by tool name and there's no fixed schema to model against.
 */
public record ToolUseBlock(String name, Object input) implements ContentBlock {
}
