package com.claude.ingestor.model;

/**
 * The result of a tool call. {@code content} is normalized to plain text
 * (a raw tool_result's own {@code content} can itself be a string or a
 * nested block array; the mapper flattens either into text here, since
 * that's what every current consumer of this data actually wants).
 */
public record ToolResultBlock(String content, boolean isError) implements ContentBlock {
}
