package com.claude.ingestor.model;

/**
 * Basic build/runtime info returned by {@code GET /api/info}.
 * {@code version} is hand-set for now; a later phase can wire it from the
 * Maven build ({@code ${project.version}} via resource filtering) instead.
 */
public record VersionInfo(
        String applicationName,
        String version,
        String javaVersion,
        String startedAt
) {
}
