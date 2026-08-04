package com.claude.ingestor.watcher;

/**
 * What happened to a watched file.
 *
 * {@link #DISCOVERED} is distinct from {@link #CREATED}: it's used for
 * files that already existed when the watcher started (so downstream
 * phases know these are pre-existing history, not brand-new activity),
 * whereas {@link #CREATED} means the file appeared while the watcher was
 * already running.
 */
public enum FileChangeKind {
    DISCOVERED,
    CREATED,
    MODIFIED,
    DELETED
}