package com.claude.ingestor.analytics;

import java.util.Optional;
import org.springframework.stereotype.Component;

@Component
public class StoryPointEstimateService {

    private final StoryPointProperties properties;

    public StoryPointEstimateService(StoryPointProperties properties) {
        this.properties = properties;
    }

    /** Expected duration range for a story point value, or empty if unmapped. */
    public Optional<StoryPointDayRange> expectedRange(int storyPoints) {
        if (properties.mapping() == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(properties.mapping().get(String.valueOf(storyPoints)));
    }

    /**
     * Compares {@code actualDays} against the expected range for
     * {@code storyPoints}. {@code verdict} is {@code "unknown"} (not
     * "under"/"within"/"over") if there's no configured range for that
     * point value - check {@code claude.story-points.mapping} rather than
     * treating "unknown" as "under" or assuming a typo elsewhere.
     */
    public StoryPointAssessment assess(int storyPoints, double actualDays) {
        Optional<StoryPointDayRange> range = expectedRange(storyPoints);
        if (range.isEmpty()) {
            return new StoryPointAssessment(storyPoints, null, actualDays, "unknown");
        }

        StoryPointDayRange r = range.get();
        String verdict;
        if (actualDays < r.minDays()) {
            verdict = "under";
        } else if (actualDays > r.maxDays()) {
            verdict = "over";
        } else {
            verdict = "within";
        }
        return new StoryPointAssessment(storyPoints, r, actualDays, verdict);
    }
}
