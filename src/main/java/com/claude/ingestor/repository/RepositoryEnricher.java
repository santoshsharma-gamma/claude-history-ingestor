package com.claude.ingestor.repository;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Enriches a project directory (a {@code ClaudeEvent.cwd()}) with a
 * detected repo name and technology stack, by running every
 * {@link TechnologyDetector} bean in the context against it.
 *
 * Results are cached per (normalized, absolute) directory path - a
 * project's tech stack essentially never changes between one message and
 * the next, and running every detector on every single event would mean
 * a filesystem scan (several {@code Files.exists} calls, a directory
 * listing for Terraform, a file read for package.json) per event, for no
 * benefit. A restart clears the cache and re-detects from scratch, same
 * trade-off {@code ProjectRegistry} (Phase 2) already made.
 */
@Component
public class RepositoryEnricher {

    private static final Logger log = LoggerFactory.getLogger(RepositoryEnricher.class);

    private final List<TechnologyDetector> detectors;
    private final Clock clock;
    private final Map<String, RepositoryEnrichment> cache = new ConcurrentHashMap<>();

    public RepositoryEnricher(List<TechnologyDetector> detectors, Clock clock) {
        this.detectors = detectors;
        this.clock = clock;
    }

    public RepositoryEnrichment enrich(String cwd) {
        if (cwd == null || cwd.isBlank()) {
            return RepositoryEnrichment.UNKNOWN;
        }

        String repoName = repoNameOf(cwd);

        Path dir;
        try {
            dir = Path.of(cwd).toAbsolutePath().normalize();
        } catch (Exception e) {
            log.debug("Could not interpret cwd '{}' as a filesystem path for technology detection: {} "
                            + "(repo name is still derived from the raw string, independently, so this is harmless)",
                    cwd, e.getMessage());
            return new RepositoryEnrichment(repoName, Set.of(), Instant.now(clock));
        }

        return cache.computeIfAbsent(cwd, key -> detect(dir, repoName));
    }

    private RepositoryEnrichment detect(Path dir, String repoName) {
        if (!Files.isDirectory(dir)) {
            // Common and structurally expected, not just "sometimes
            // harmless": in the Docker deployment (see docker-compose.yml),
            // only CLAUDE_HISTORY_SOURCE is mounted into the container -
            // the actual project source trees `cwd` points at are NOT
            // mounted (there's no practical way to mount every repo a
            // person might ever `cd` into), so technology detection will
            // essentially always find nothing when running that way. It
            // also legitimately happens outside Docker if a project was
            // deleted, moved, or this runs against a different machine's
            // history than the one that produced it. Either way, repo name
            // is unaffected - it's derived from the cwd string itself, not
            // from anything requiring filesystem access.
            log.debug("'{}' is not visible as a directory to this process - reporting repo name '{}' only, "
                    + "no technologies", dir, repoName);
            return new RepositoryEnrichment(repoName, Set.of(), Instant.now(clock));
        }

        Set<String> technologies = new LinkedHashSet<>();
        for (TechnologyDetector detector : detectors) {
            try {
                if (!detector.matches(dir)) {
                    continue;
                }
                // NodeJsDetector gets a chance to report something more
                // specific (React/Vue) than its own technologyName().
                String name = (detector instanceof NodeJsDetector njd) ? njd.refine(dir) : detector.technologyName();
                technologies.add(name);
            } catch (Exception e) {
                // One detector's failure shouldn't block the others, or the
                // whole enrichment, from completing.
                log.debug("Detector '{}' failed on '{}': {}", detector.technologyName(), dir, e.getMessage());
            }
        }

        log.debug("Enriched '{}' -> repo={}, technologies={}", dir, repoName, technologies);
        return new RepositoryEnrichment(repoName, technologies, Instant.now(clock));
    }

    /**
     * Extracts the last path segment from a raw {@code cwd} string via
     * pure string manipulation - deliberately NOT {@code java.nio.file.Path},
     * whose separator handling follows whatever OS the JVM itself is
     * running on. {@code Path.of(...)} on Linux only splits on {@code /},
     * so a Windows-recorded cwd like {@code C:\Users\x\project} - exactly
     * what Claude Code on Windows records, and exactly what this process
     * sees when running inside the Linux container from Phase 11's
     * docker-compose.yml - would come back as one single opaque "path
     * segment" (the whole string), not {@code project}. This was a real
     * bug, caught from an actual Windows-sourced record showing up as
     * {@code repo_name: "C:\Users\...\project"} in OpenObserve instead of
     * just {@code project}. Handling both separators explicitly, regardless
     * of the host OS, fixes it for every deployment shape at once.
     */
    private static String repoNameOf(String cwd) {
        String normalized = cwd.replace('\\', '/');
        while (normalized.length() > 1 && normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        int lastSlash = normalized.lastIndexOf('/');
        String name = lastSlash >= 0 ? normalized.substring(lastSlash + 1) : normalized;
        return name.isBlank() ? "unknown" : name;
    }
}