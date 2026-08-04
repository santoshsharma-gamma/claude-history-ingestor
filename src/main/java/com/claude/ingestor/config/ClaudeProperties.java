package com.claude.ingestor.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Where to find Claude Code's local history files.
 *
 * Bound from the {@code claude.*} keys in application.yml, e.g.:
 * <pre>
 * claude:
 *   history-path: /home/me/.claude/projects
 *   file-pattern: "*.jsonl"
 * </pre>
 */
@ConfigurationProperties(prefix = "claude")
public record ClaudeProperties(

        /** Directory to (recursively, from Phase 2 onward) scan for history files. */
        String historyPath,

        /** Glob used to select history files within {@link #historyPath}. */
        @DefaultValue("*.jsonl") String filePattern
) {
}
