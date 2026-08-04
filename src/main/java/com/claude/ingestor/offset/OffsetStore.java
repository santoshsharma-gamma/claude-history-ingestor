package com.claude.ingestor.offset;

import java.nio.file.Path;

/**
 * Tracks how far each watched file has been read, so re-processing after a
 * restart (or after a burst of append events) only looks at new bytes.
 *
 * For Phase 3, {@link OffsetTrackingListener} commits optimistically to
 * end-of-file at detection time - this keeps offset tracking independently
 * testable before a parser exists. Phase 4 will tighten this: once it can
 * actually parse lines, it should call {@link #advanceOffset} with the
 * position just after the last <em>complete</em> line it consumed, not
 * blindly to file size, since a MODIFY event can fire while a line is
 * still being written.
 */
public interface OffsetStore {

    /** Last committed read offset for {@code file}, or 0 if never seen. */
    long getOffset(Path file);

    /** Records that {@code file} has been read up to {@code newOffset} bytes. */
    void advanceOffset(Path file, long newOffset);

    /** Forgets a file entirely (e.g. on a DELETED event). */
    void remove(Path file);
}