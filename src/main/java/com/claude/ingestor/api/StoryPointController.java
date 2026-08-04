package com.claude.ingestor.api;

import com.claude.ingestor.analytics.StoryPointAssessment;
import com.claude.ingestor.analytics.StoryPointDayRange;
import com.claude.ingestor.analytics.StoryPointEstimateService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Exposes {@link StoryPointEstimateService} over HTTP. Story points aren't
 * part of the Claude Code / OpenObserve data this app otherwise works
 * with - this is a standalone reference lookup, meant to be combined with
 * actual measured duration from elsewhere (e.g. the JIRA-vs-usage
 * PowerShell scripts) rather than something this app derives on its own.
 */
@RestController
@RequestMapping("/story-points")
public class StoryPointController {

    private final StoryPointEstimateService service;

    public StoryPointController(StoryPointEstimateService service) {
        this.service = service;
    }

    /** Expected duration range for a story point value. 404 if unmapped. */
    @GetMapping("/{points}")
    public ResponseEntity<StoryPointDayRange> expectedRange(@PathVariable int points) {
        return service.expectedRange(points)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * Compares {@code actualDays} against the expected range for
     * {@code points}. Always returns 200, even for an unmapped story
     * point value - check the response's {@code verdict} field
     * ({@code "unknown"} means no mapping exists) rather than relying on
     * HTTP status here.
     */
    @GetMapping("/{points}/assess")
    public StoryPointAssessment assess(@PathVariable int points, @RequestParam double actualDays) {
        return service.assess(points, actualDays);
    }
}
