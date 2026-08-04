package com.claude.ingestor.offset;

import java.nio.file.Path;
import java.time.Instant;

/**
 * Published when {@link OffsetTrackingListener} notices a file has grown
 * (or been created/rediscovered) past its last committed offset.
 *
 * {@code toOffset} is the file size at detection time, which is committed
 * immediately in Phase 3 (see {@link OffsetStore}'s note on this). It may
 * land mid-line if something is actively writing when the event fires -
 * Phase 4's parser should tolerate a trailing incomplete line in the range
 * it's handed, and over time the commit point will move to "last complete
 * line consumed" rather than "file size at detection".
 */
public record NewContentAvailableEvent(
        Path filePath,
        String projectName,
        long fromOffset,
        long toOffset,
        Instant detectedAt
) {
}
