package com.claude.ingestor.api;

import com.claude.ingestor.analytics.ActivityHighlights;
import com.claude.ingestor.analytics.DailyCostPoint;
import com.claude.ingestor.analytics.DailyMetrics;
import com.claude.ingestor.analytics.MetricsAccumulator;
import com.claude.ingestor.analytics.ModelBreakdown;
import com.claude.ingestor.analytics.RepoBreakdown;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Exposes {@link MetricsAccumulator} over HTTP - the five endpoints from
 * the original roadmap.
 */
@RestController
@RequestMapping("/analytics")
public class AnalyticsController {

    private final MetricsAccumulator accumulator;

    public AnalyticsController(MetricsAccumulator accumulator) {
        this.accumulator = accumulator;
    }

    /** Today's prompts/cost/sessions/engineering-score. */
    @GetMapping("/daily")
    public DailyMetrics daily() {
        return accumulator.dailyMetrics();
    }

    /** All-time activity per repository. */
    @GetMapping("/repositories")
    public List<RepoBreakdown> repositories() {
        return accumulator.repoBreakdowns();
    }

    /** All-time usage/cost per model. */
    @GetMapping("/models")
    public List<ModelBreakdown> models() {
        return accumulator.modelBreakdowns();
    }

    /** Daily cost trend. {@code days} defaults to 30 and is clamped to [1, 365]. */
    @GetMapping("/cost")
    public List<DailyCostPoint> cost(@RequestParam(defaultValue = "30") int days) {
        int clamped = Math.max(1, Math.min(days, 365));
        return accumulator.costHistory(clamped);
    }

    /** All-time highlights: most active repo, longest session, most expensive prompt, top technology. */
    @GetMapping("/activity")
    public ActivityHighlights activity() {
        return accumulator.activityHighlights();
    }
}