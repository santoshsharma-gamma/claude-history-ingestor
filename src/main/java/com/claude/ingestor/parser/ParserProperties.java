package com.claude.ingestor.parser;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Tuning knobs for how {@link JsonlLineReader} reads byte ranges.
 *
 * {@code chunkSizeBytes} bounds memory use when reading a large range in
 * one go - important given the roadmap's own example of a 1.2 GB session
 * file: we never allocate a buffer anywhere near that size, regardless of
 * how large the requested {@code [fromOffset, toOffset)} range is.
 */
@ConfigurationProperties(prefix = "claude.parser")
public record ParserProperties(

        @DefaultValue("1048576") int chunkSizeBytes,          // 1 MiB
        @DefaultValue("2000") int maxRawLineLengthLogged        // for parse-failure log lines
) {
}