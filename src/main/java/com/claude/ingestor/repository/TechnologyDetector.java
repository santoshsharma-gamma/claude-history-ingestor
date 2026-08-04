package com.claude.ingestor.repository;

import java.nio.file.Path;

/**
 * Detects whether a project directory uses a particular technology, based
 * on marker files (a {@code pom.xml}, a {@code go.mod}, etc). Every
 * detector bean in the context is applied to every project directory (see
 * {@link RepositoryEnricher}), so a repo can match more than one - a repo
 * with both a Java backend and Terraform infra is both "Java (Maven)" and
 * "Terraform", not one or the other.
 *
 * Implementations should never throw - {@link RepositoryEnricher} catches
 * defensively either way, but a detector that fails cleanly (returns
 * {@code false} on any I/O trouble) is easier to reason about than one
 * that relies on the caller's safety net.
 */
public interface TechnologyDetector {

    /** Human-readable technology name, e.g. {@code "Java (Maven)"}, {@code "Terraform"}. */
    String technologyName();

    /** Whether {@code projectDir} looks like it uses this technology. */
    boolean matches(Path projectDir);
}