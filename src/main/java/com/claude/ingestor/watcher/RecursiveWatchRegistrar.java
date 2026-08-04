package com.claude.ingestor.watcher;

import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Map;
import org.springframework.stereotype.Component;

import static java.nio.file.StandardWatchEventKinds.ENTRY_CREATE;
import static java.nio.file.StandardWatchEventKinds.ENTRY_DELETE;
import static java.nio.file.StandardWatchEventKinds.ENTRY_MODIFY;

/**
 * Registers a directory tree with a {@link WatchService}.
 *
 * Java's WatchService only reports events for directories you've
 * explicitly registered, and registering a directory is not recursive —
 * so both the initial walk of {@code claude.history-path} and any later
 * "a new subdirectory just appeared" case need to go through here.
 */
@Component
public class RecursiveWatchRegistrar {

    /**
     * Walks {@code root} (which must already exist) and registers it plus
     * every subdirectory beneath it with {@code service}, recording each
     * resulting {@link WatchKey}'s directory in {@code keyToDir} so the
     * watcher can map events back to a path later.
     */
    public void registerTree(Path root, WatchService service, Map<WatchKey, Path> keyToDir) throws IOException {
        Files.walkFileTree(root, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
                register(dir, service, keyToDir);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    /** Registers a single directory (not its children) with the watch service. */
    public void register(Path dir, WatchService service, Map<WatchKey, Path> keyToDir) throws IOException {
        WatchKey key = dir.register(service, ENTRY_CREATE, ENTRY_MODIFY, ENTRY_DELETE);
        keyToDir.put(key, dir);
    }
}