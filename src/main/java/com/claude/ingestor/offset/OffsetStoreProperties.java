package com.claude.ingestor.offset;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Where read offsets are persisted, so a restart doesn't mean re-reading
 * every {@code .jsonl} file (some of which, per the roadmap, can be well
 * over a gigabyte) from byte zero.
 *
 * No {@code @DefaultValue} here on purpose: {@code @DefaultValue("${user.home}/...")}
 * is a known Spring Boot footgun (see spring-projects/spring-boot#29495) -
 * the placeholder is only resolved when the user's own config value
 * contains it, not when the annotation's default is what actually gets
 * used. The real default (with {@code ${user.home}} correctly resolved)
 * lives in application.yml instead, same as {@code claude.history-path}
 * in Phase 1.
 */
@ConfigurationProperties(prefix = "claude.offset-store")
public record OffsetStoreProperties(
        String path
) {
}