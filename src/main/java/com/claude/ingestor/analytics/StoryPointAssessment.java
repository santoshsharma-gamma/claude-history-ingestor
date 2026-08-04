package com.claude.ingestor.analytics;

/**
 * {@code verdict} is one of {@code "under"} (finished faster than
 * expected), {@code "within"} (inside the expected range), {@code "over"}
 * (took longer than expected), or {@code "unknown"} (no mapping exists
 * for that story point value - check {@code claude.story-points.mapping}).
 */
public record StoryPointAssessment(
        int storyPoints,
        StoryPointDayRange expectedRange,
        double actualDays,
        String verdict
) {
}
