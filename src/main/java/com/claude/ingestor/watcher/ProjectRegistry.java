package com.claude.ingestor.watcher;

import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.util.Collection;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * Tracks every project directory the watcher has seen so far. Kept as a
 * simple in-memory map for now; a later phase can back this with
 * persistence if the app needs to remember projects across restarts
 * (right now, a restart just rediscovers them from the filesystem, which
 * is fine since {@link ClaudeHistoryWatcher} re-scans on startup anyway).
 */
@Component
public class ProjectRegistry {

    private final Clock clock;
    private final Map<String, ProjectDirectory> projects = new ConcurrentHashMap<>();

    public ProjectRegistry(Clock clock) {
        this.clock = clock;
    }

    /** Registers a project the first time it's seen; no-op if already known. */
    public ProjectDirectory registerIfAbsent(String name, Path path) {
        return projects.computeIfAbsent(name, n -> new ProjectDirectory(n, path, Instant.now(clock)));
    }

    public Collection<ProjectDirectory> all() {
        return projects.values();
    }

    public int size() {
        return projects.size();
    }

    public boolean isKnown(String name) {
        return projects.containsKey(name);
    }
}
