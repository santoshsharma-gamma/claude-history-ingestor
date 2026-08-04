package com.claude.ingestor.analytics;

import java.util.Map;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Maps JIRA story points to an expected duration range, in days -
 * configured under {@code claude.story-points.mapping} in application.yml.
 *
 * Story points aren't part of the Claude Code / OpenObserve data this
 * project otherwise works with at all (they're a JIRA field) - this
 * mapping exists purely as a reference table for comparing against
 * actual measured usage duration (e.g. from the JIRA-vs-usage
 * verification scripts), not something this app derives on its own.
 *
 * Keys are bound as strings (e.g. {@code "1"}, {@code "2"}) rather than
 * as a {@code Map<Integer, ...>}, to avoid any ambiguity in how Spring
 * Boot's relaxed binder treats numeric-looking YAML map keys - a string
 * key sidesteps the question entirely rather than assuming.
 */
@ConfigurationProperties(prefix = "claude.story-points")
public record StoryPointProperties(
        Map<String, StoryPointDayRange> mapping
) {
}
