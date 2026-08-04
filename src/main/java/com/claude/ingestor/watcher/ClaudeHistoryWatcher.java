package com.claude.ingestor.watcher;

import com.claude.ingestor.config.ClaudeProperties;
import java.io.IOException;
import java.nio.file.ClosedWatchServiceException;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.PathMatcher;
import java.nio.file.WatchEvent;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.time.Clock;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Stream;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

import static java.nio.file.StandardWatchEventKinds.ENTRY_CREATE;
import static java.nio.file.StandardWatchEventKinds.ENTRY_DELETE;
import static java.nio.file.StandardWatchEventKinds.ENTRY_MODIFY;
import static java.nio.file.StandardWatchEventKinds.OVERFLOW;

/**
 * Recursively watches {@code claude.history-path} for files matching
 * {@code claude.file-pattern}, publishing a {@link FileChangeEvent} for
 * every discovered/created/modified/deleted match and registering each
 * top-level project directory (e.g. {@code asset-search},
 * {@code terraform}) with the {@link ProjectRegistry} as it's seen.
 *
 * This phase doesn't read file contents at all — that's Phase 3 (offsets)
 * and Phase 4 (parsing). It only answers "something changed, here's the
 * path and which project it belongs to."
 */
@Component
public class ClaudeHistoryWatcher implements SmartLifecycle {

    private static final Logger log = LoggerFactory.getLogger(ClaudeHistoryWatcher.class);

    private final ClaudeProperties claudeProperties;
    private final ApplicationEventPublisher publisher;
    private final RecursiveWatchRegistrar registrar;
    private final ProjectRegistry projectRegistry;
    private final Clock clock;
    private final PathMatcher fileMatcher;

    private final Map<WatchKey, Path> keyToDir = new ConcurrentHashMap<>();

    private ExecutorService executor;
    private WatchService watchService;
    private Path root;
    private volatile boolean running = false;

    public ClaudeHistoryWatcher(ClaudeProperties claudeProperties,
                                ApplicationEventPublisher publisher,
                                RecursiveWatchRegistrar registrar,
                                ProjectRegistry projectRegistry,
                                Clock clock) {
        this.claudeProperties = claudeProperties;
        this.publisher = publisher;
        this.registrar = registrar;
        this.projectRegistry = projectRegistry;
        this.clock = clock;
        this.fileMatcher = FileSystems.getDefault().getPathMatcher("glob:" + claudeProperties.filePattern());
    }

    @Override
    public void start() {
        root = Path.of(claudeProperties.historyPath()).toAbsolutePath().normalize();

        if (!Files.isDirectory(root)) {
            log.warn("Claude history path '{}' does not exist (yet) - watcher will not start. "
                    + "Create it (or fix claude.history-path) and restart the app to pick it up.", root);
            return;
        }

        try {
            watchService = FileSystems.getDefault().newWatchService();
            registrar.registerTree(root, watchService, keyToDir);
            discoverExistingFiles();

            executor = Executors.newSingleThreadExecutor(r -> {
                Thread t = new Thread(r, "claude-history-watcher");
                t.setDaemon(true);
                return t;
            });
            running = true;
            executor.submit(this::watchLoop);

            log.info("Watching '{}' for '{}' files ({} project(s) discovered so far: {})",
                    root, claudeProperties.filePattern(), projectRegistry.size(),
                    projectRegistry.all().stream().map(ProjectDirectory::name).toList());
        } catch (IOException e) {
            log.error("Failed to start watcher on '{}': {}", root, e.getMessage(), e);
        }
    }

    @Override
    public void stop() {
        running = false;
        if (executor != null) {
            executor.shutdownNow();
        }
        if (watchService != null) {
            try {
                watchService.close();
            } catch (IOException e) {
                log.debug("Error closing watch service: {}", e.getMessage());
            }
        }
        keyToDir.clear();
    }

    @Override
    public boolean isRunning() {
        return running;
    }

    /** Start late, stop early - runs after regular application beans are up. */
    @Override
    public int getPhase() {
        return Integer.MAX_VALUE;
    }

    private void discoverExistingFiles() throws IOException {
        try (Stream<Path> walk = Files.walk(root)) {
            walk.filter(Files::isRegularFile)
                    .filter(p -> fileMatcher.matches(p.getFileName()))
                    .forEach(p -> publishEvent(p, FileChangeKind.DISCOVERED));
        }
    }

    private void watchLoop() {
        while (running) {
            WatchKey key;
            try {
                key = watchService.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            } catch (ClosedWatchServiceException e) {
                break;
            }

            Path dir = keyToDir.get(key);
            if (dir == null) {
                key.reset();
                continue;
            }

            for (WatchEvent<?> event : key.pollEvents()) {
                if (event.kind() == OVERFLOW) {
                    log.warn("Watch overflow for '{}' - some events may have been missed", dir);
                    continue;
                }

                @SuppressWarnings("unchecked")
                WatchEvent<Path> pathEvent = (WatchEvent<Path>) event;
                Path changed = dir.resolve(pathEvent.context());

                if (event.kind() == ENTRY_CREATE && Files.isDirectory(changed)) {
                    registerNewDirectory(changed);
                    continue;
                }

                if (!fileMatcher.matches(changed.getFileName())) {
                    continue;
                }

                if (event.kind() == ENTRY_CREATE) {
                    publishEvent(changed, FileChangeKind.CREATED);
                } else if (event.kind() == ENTRY_MODIFY) {
                    publishEvent(changed, FileChangeKind.MODIFIED);
                } else if (event.kind() == ENTRY_DELETE) {
                    publishEvent(changed, FileChangeKind.DELETED);
                }
            }

            boolean valid = key.reset();
            if (!valid) {
                keyToDir.remove(key);
            }
        }
    }

    private void registerNewDirectory(Path dir) {
        try {
            registrar.registerTree(dir, watchService, keyToDir);
            log.debug("Registered new directory for watching: {}", dir);
            // Pick up files that landed in the same instant as the directory
            // itself (e.g. a project copied in one shot rather than
            // mkdir-then-write-files).
            try (Stream<Path> walk = Files.walk(dir)) {
                walk.filter(Files::isRegularFile)
                        .filter(p -> fileMatcher.matches(p.getFileName()))
                        .forEach(p -> publishEvent(p, FileChangeKind.DISCOVERED));
            }
        } catch (IOException e) {
            log.warn("Failed to register new directory '{}': {}", dir, e.getMessage());
        }
    }

    private void publishEvent(Path file, FileChangeKind kind) {
        String projectName = projectNameOf(file);
        projectRegistry.registerIfAbsent(projectName, projectDirOf(file));

        FileChangeEvent event = new FileChangeEvent(file, projectName, kind, Instant.now(clock));
        log.debug("{} {} (project: {})", kind, file, projectName);
        publisher.publishEvent(event);
    }

    /**
     * A file's project is the name of the first directory under
     * {@code root} on its path - e.g. for
     * {@code <root>/asset-search/session-1.jsonl} that's "asset-search".
     * Files directly under root (no project subdirectory) fall back to
     * "_root".
     */
    private String projectNameOf(Path file) {
        Path relative = root.relativize(file.toAbsolutePath());
        return relative.getNameCount() > 1 ? relative.getName(0).toString() : "_root";
    }

    private Path projectDirOf(Path file) {
        Path relative = root.relativize(file.toAbsolutePath());
        return relative.getNameCount() > 1 ? root.resolve(relative.getName(0)) : root;
    }
}