package com.claude.ingestor.offset;

import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Persists offsets to a flat {@link Properties} file (one
 * {@code /absolute/path/to/file.jsonl=1234} line per tracked file). Chosen
 * over a database for Phase 3 because it's zero-dependency, human
 * readable, trivial to inspect/edit by hand while developing, and more
 * than fast enough for "hundreds of session files," which is the actual
 * scale here.
 *
 * Writes are atomic (write to a temp file, then {@code move} with
 * {@code ATOMIC_MOVE}) so a crash mid-write can't corrupt the store into
 * an unreadable state.
 */
@Component
public class PropertiesFileOffsetStore implements OffsetStore {

    private static final Logger log = LoggerFactory.getLogger(PropertiesFileOffsetStore.class);

    private final Path storeFile;
    private final Map<String, Long> offsets = new ConcurrentHashMap<>();

    public PropertiesFileOffsetStore(OffsetStoreProperties properties) {
        this.storeFile = Path.of(properties.path()).toAbsolutePath().normalize();
    }

    @PostConstruct
    void load() {
        try {
            Path parent = storeFile.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
        } catch (IOException e) {
            log.error("Could not create directory for offset store '{}': {}", storeFile, e.getMessage(), e);
            return;
        }

        if (!Files.exists(storeFile)) {
            log.info("No existing offset store at '{}' - starting fresh", storeFile);
            return;
        }

        Properties props = new Properties();
        try (Reader reader = Files.newBufferedReader(storeFile, StandardCharsets.UTF_8)) {
            props.load(reader);
        } catch (IOException e) {
            log.error("Failed to read offset store '{}': {} - starting with no offsets remembered",
                    storeFile, e.getMessage(), e);
            return;
        }

        int loaded = 0;
        for (String key : props.stringPropertyNames()) {
            try {
                offsets.put(key, Long.parseLong(props.getProperty(key)));
                loaded++;
            } catch (NumberFormatException e) {
                log.warn("Skipping malformed offset entry for '{}' in '{}'", key, storeFile);
            }
        }
        log.info("Loaded {} offset(s) from '{}'", loaded, storeFile);
    }

    @Override
    public long getOffset(Path file) {
        return offsets.getOrDefault(keyOf(file), 0L);
    }

    @Override
    public void advanceOffset(Path file, long newOffset) {
        offsets.put(keyOf(file), newOffset);
        persist();
    }

    @Override
    public void remove(Path file) {
        offsets.remove(keyOf(file));
        persist();
    }

    private String keyOf(Path file) {
        return file.toAbsolutePath().normalize().toString();
    }

    private synchronized void persist() {
        Properties props = new Properties();
        for (Map.Entry<String, Long> entry : offsets.entrySet()) {
            props.setProperty(entry.getKey(), String.valueOf(entry.getValue()));
        }

        Path tmp = storeFile.resolveSibling(storeFile.getFileName() + ".tmp");
        try (Writer writer = Files.newBufferedWriter(tmp, StandardCharsets.UTF_8)) {
            props.store(writer, "Claude history ingestor - file read offsets");
        } catch (IOException e) {
            log.error("Failed to write offset store temp file '{}': {}", tmp, e.getMessage(), e);
            return;
        }

        try {
            Files.move(tmp, storeFile, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            log.error("Failed to commit offset store '{}': {}", storeFile, e.getMessage(), e);
        }
    }
}