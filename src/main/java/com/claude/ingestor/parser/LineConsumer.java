package com.claude.ingestor.parser;

/**
 * Callback invoked once per complete line found while reading a byte
 * range. A dedicated interface rather than a stock {@code java.util.function}
 * one because we need three arguments (text plus its exact byte span) -
 * the offsets matter for accurate offset-store commits, not just logging.
 */
@FunctionalInterface
public interface LineConsumer {

    /**
     * @param line              the line's text, decoded as UTF-8, without its line terminator
     * @param startOffset       absolute byte offset in the file where this line begins
     * @param endOffsetExclusive absolute byte offset right after this line's terminator
     */
    void accept(String line, long startOffset, long endOffsetExclusive);
}