package com.claude.ingestor.analytics;

/** Expected duration range (in days) for a given story point value. */
public record StoryPointDayRange(
        int minDays,
        int maxDays
) {
}
