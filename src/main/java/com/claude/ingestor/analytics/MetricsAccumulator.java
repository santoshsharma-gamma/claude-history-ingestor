package com.claude.ingestor.analytics;

import com.claude.ingestor.model.ClaudeEvent;
import com.claude.ingestor.model.ContentBlock;
import com.claude.ingestor.model.TextBlock;
import com.claude.ingestor.repository.EnrichedClaudeEvent;
import com.claude.ingestor.repository.RepositoryEnrichment;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.DoubleAdder;
import java.util.concurrent.atomic.LongAdder;
import org.springframework.stereotype.Component;

/**
 * Ingests every {@link EnrichedClaudeEvent} and maintains all the running
 * state {@link AnalyticsSnapshot} is built from: per-day rollups (prompts,
 * cost, sessions, distinct repos/technologies, error rate) and all-time
 * rollups (most active repo, longest session, most expensive prompt, top
 * technology).
 *
 * Kept as one cohesive stateful engine rather than several coordinating
 * micro-trackers - snapshotting needs a consistent read across several of
 * these maps at once (e.g. today's distinct-repo count feeds the
 * engineering score), which is far simpler to reason about with one
 * class than with several trackers that would need their own
 * synchronization to agree on "the same moment".
 *
 * All state is in-memory only - a restart loses all history and starts
 * counting from zero. Fine for a "how's today going" dashboard; worth
 * revisiting (persistence, or rebuilding from OpenObserve query results)
 * if historical trends across restarts ever matter.
 */
@Component
public class MetricsAccumulator {

    private final ZoneId zone;
    private final Clock clock;
    private final CostCalculator costCalculator;
    private final EngineeringScoreCalculator scoreCalculator;

    private final Map<String, SessionAcc> sessions = new ConcurrentHashMap<>();
    private final Map<LocalDate, LongAdder> promptsByDay = new ConcurrentHashMap<>();
    private final Map<LocalDate, DoubleAdder> costByDay = new ConcurrentHashMap<>();
    private final Map<LocalDate, Set<String>> sessionsByDay = new ConcurrentHashMap<>();
    private final Map<LocalDate, Set<String>> reposByDay = new ConcurrentHashMap<>();
    private final Map<LocalDate, Set<String>> technologiesByDay = new ConcurrentHashMap<>();
    private final Map<LocalDate, LongAdder> eventsByDay = new ConcurrentHashMap<>();
    private final Map<LocalDate, LongAdder> errorsByDay = new ConcurrentHashMap<>();
    private final Map<String, LongAdder> technologyCountsAllTime = new ConcurrentHashMap<>();
    private final Map<String, LongAdder> repoEventCountsAllTime = new ConcurrentHashMap<>();
    private final Map<String, LongAdder> repoPromptCountsAllTime = new ConcurrentHashMap<>();
    private final Map<String, DoubleAdder> repoCostAllTime = new ConcurrentHashMap<>();
    private final Map<String, Instant> repoLastActiveAt = new ConcurrentHashMap<>();
    private final Map<String, Set<String>> repoTechnologiesAllTime = new ConcurrentHashMap<>();
    private final Map<String, LongAdder> modelEventCounts = new ConcurrentHashMap<>();
    private final Map<String, LongAdder> modelInputTokens = new ConcurrentHashMap<>();
    private final Map<String, LongAdder> modelOutputTokens = new ConcurrentHashMap<>();
    private final Map<String, DoubleAdder> modelCostAllTime = new ConcurrentHashMap<>();

    private volatile MostExpensivePrompt mostExpensivePrompt;

    public MetricsAccumulator(AnalyticsProperties properties, Clock clock, CostCalculator costCalculator,
                              EngineeringScoreCalculator scoreCalculator) {
        this.zone = ZoneId.of(properties.timezone());
        this.clock = clock;
        this.costCalculator = costCalculator;
        this.scoreCalculator = scoreCalculator;
    }

    public void record(EnrichedClaudeEvent enriched) {
        ClaudeEvent event = enriched.event();
        String sessionId = event.sessionId();
        if (sessionId == null) {
            return; // nothing meaningful to attribute this event to
        }

        RepositoryEnrichment enrichment = enriched.enrichment();
        String repoName = enrichment != null ? enrichment.repoName() : "unknown";
        Set<String> technologies = enrichment != null ? enrichment.technologies() : Set.of();
        Instant timestamp = event.timestamp() != null ? event.timestamp() : Instant.now(clock);
        boolean isPrompt = PromptClassifier.isPrompt(event);
        boolean isError = event.toolUseResult() != null && event.toolUseResult().isError();
        double cost = event.message() != null ? costCalculator.costOf(event.message().model(), event.message().usage()) : 0.0;

        sessions.computeIfAbsent(sessionId, k -> new SessionAcc(repoName, timestamp))
                .update(timestamp, isPrompt, cost);

        LocalDate day = timestamp.atZone(zone).toLocalDate();
        eventsByDay.computeIfAbsent(day, d -> new LongAdder()).increment();
        if (isError) {
            errorsByDay.computeIfAbsent(day, d -> new LongAdder()).increment();
        }
        if (isPrompt) {
            promptsByDay.computeIfAbsent(day, d -> new LongAdder()).increment();
        }
        costByDay.computeIfAbsent(day, d -> new DoubleAdder()).add(cost);
        sessionsByDay.computeIfAbsent(day, d -> ConcurrentHashMap.newKeySet()).add(sessionId);
        reposByDay.computeIfAbsent(day, d -> ConcurrentHashMap.newKeySet()).add(repoName);
        for (String tech : technologies) {
            technologiesByDay.computeIfAbsent(day, d -> ConcurrentHashMap.newKeySet()).add(tech);
            technologyCountsAllTime.computeIfAbsent(tech, t -> new LongAdder()).increment();
        }
        repoEventCountsAllTime.computeIfAbsent(repoName, r -> new LongAdder()).increment();
        if (isPrompt) {
            repoPromptCountsAllTime.computeIfAbsent(repoName, r -> new LongAdder()).increment();
        }
        repoCostAllTime.computeIfAbsent(repoName, r -> new DoubleAdder()).add(cost);
        repoLastActiveAt.merge(repoName, timestamp, (a, b) -> a.isAfter(b) ? a : b);
        if (!technologies.isEmpty()) {
            repoTechnologiesAllTime.computeIfAbsent(repoName, r -> ConcurrentHashMap.newKeySet()).addAll(technologies);
        }

        if (event.message() != null && event.message().model() != null) {
            String model = event.message().model();
            modelEventCounts.computeIfAbsent(model, m -> new LongAdder()).increment();
            if (event.message().usage() != null) {
                modelInputTokens.computeIfAbsent(model, m -> new LongAdder()).add(event.message().usage().inputTokens());
                modelOutputTokens.computeIfAbsent(model, m -> new LongAdder()).add(event.message().usage().outputTokens());
            }
            modelCostAllTime.computeIfAbsent(model, m -> new DoubleAdder()).add(cost);
        }

        if (cost > 0 && (mostExpensivePrompt == null || cost > mostExpensivePrompt.costUsd())) {
            mostExpensivePrompt = buildMostExpensivePrompt(event, repoName, cost, timestamp);
        }
    }

    public AnalyticsSnapshot snapshot() {
        LocalDate today = LocalDate.now(clock.withZone(zone));

        long promptsToday = sum(promptsByDay.get(today));
        double costToday = sum(costByDay.get(today));
        int sessionsToday = size(sessionsByDay.get(today));
        int distinctReposToday = size(reposByDay.get(today));
        int distinctTechnologiesToday = size(technologiesByDay.get(today));
        long eventsToday = sum(eventsByDay.get(today));
        long errorsToday = sum(errorsByDay.get(today));
        double errorRateToday = eventsToday > 0 ? (double) errorsToday / eventsToday : 0.0;

        String mostActiveRepo = topEntry(repoEventCountsAllTime);
        String topTechnology = topEntry(technologyCountsAllTime);
        SessionSummary longestSession = computeLongestSession();
        double engineeringScore = scoreCalculator.compute(promptsToday, distinctReposToday, distinctTechnologiesToday, errorRateToday);

        return new AnalyticsSnapshot(today, promptsToday, costToday, sessionsToday, mostActiveRepo,
                longestSession, mostExpensivePrompt, topTechnology, engineeringScore);
    }

    /** Backing data for {@code GET /analytics/daily}. */
    public DailyMetrics dailyMetrics() {
        AnalyticsSnapshot s = snapshot();
        return new DailyMetrics(s.date(), s.promptsToday(), s.costTodayUsd(), s.sessionsToday(), s.engineeringScore());
    }

    /** Backing data for {@code GET /analytics/activity}. */
    public ActivityHighlights activityHighlights() {
        AnalyticsSnapshot s = snapshot();
        return new ActivityHighlights(s.mostActiveRepo(), s.longestSession(), s.mostExpensivePrompt(), s.topTechnology());
    }

    /** Backing data for {@code GET /analytics/repositories}, one entry per repo seen (all-time), unsorted. */
    public List<RepoBreakdown> repoBreakdowns() {
        List<RepoBreakdown> result = new ArrayList<>(repoEventCountsAllTime.size());
        for (String repoName : repoEventCountsAllTime.keySet()) {
            result.add(new RepoBreakdown(
                    repoName,
                    sum(repoEventCountsAllTime.get(repoName)),
                    sum(repoPromptCountsAllTime.get(repoName)),
                    sum(repoCostAllTime.get(repoName)),
                    repoLastActiveAt.get(repoName),
                    repoTechnologiesAllTime.getOrDefault(repoName, Set.of())
            ));
        }
        return result;
    }

    /** Backing data for {@code GET /analytics/models}, one entry per model seen (all-time), unsorted. */
    public List<ModelBreakdown> modelBreakdowns() {
        List<ModelBreakdown> result = new ArrayList<>(modelEventCounts.size());
        for (String model : modelEventCounts.keySet()) {
            result.add(new ModelBreakdown(
                    model,
                    sum(modelEventCounts.get(model)),
                    sum(modelInputTokens.get(model)),
                    sum(modelOutputTokens.get(model)),
                    sum(modelCostAllTime.get(model))
            ));
        }
        return result;
    }

    /**
     * Backing data for {@code GET /analytics/cost}: the last {@code days}
     * days (inclusive of today), oldest first. Days with no recorded
     * activity appear as zeroed points rather than being omitted, so a
     * chart built from this doesn't need its own gap-filling.
     */
    public List<DailyCostPoint> costHistory(int days) {
        LocalDate today = LocalDate.now(clock.withZone(zone));
        List<DailyCostPoint> result = new ArrayList<>(days);
        for (int i = days - 1; i >= 0; i--) {
            LocalDate day = today.minusDays(i);
            result.add(new DailyCostPoint(day, sum(costByDay.get(day)), sum(promptsByDay.get(day)), size(sessionsByDay.get(day))));
        }
        return result;
    }

    private SessionSummary computeLongestSession() {
        String longestId = null;
        SessionAcc longestAcc = null;
        Duration max = Duration.ZERO;

        for (Map.Entry<String, SessionAcc> entry : sessions.entrySet()) {
            Duration duration = Duration.between(entry.getValue().firstEventAt, entry.getValue().lastEventAt);
            if (duration.compareTo(max) >= 0) {
                max = duration;
                longestId = entry.getKey();
                longestAcc = entry.getValue();
            }
        }

        if (longestAcc == null) {
            return null;
        }
        return new SessionSummary(longestId, longestAcc.repoName, longestAcc.firstEventAt, longestAcc.lastEventAt,
                max.getSeconds(), longestAcc.promptCount.sum(), longestAcc.costUsd.sum());
    }

    private MostExpensivePrompt buildMostExpensivePrompt(ClaudeEvent event, String repoName, double cost, Instant timestamp) {
        String model = event.message() != null ? event.message().model() : null;
        String snippet = extractSnippet(event);
        return new MostExpensivePrompt(event.sessionId(), repoName, model, cost, timestamp, snippet);
    }

    private String extractSnippet(ClaudeEvent event) {
        if (event.message() == null) {
            return null;
        }
        for (ContentBlock block : event.message().content()) {
            if (block instanceof TextBlock tb && tb.text() != null && !tb.text().isBlank()) {
                String text = tb.text();
                return text.length() > 200 ? text.substring(0, 200) + "..." : text;
            }
        }
        return null;
    }

    private static long sum(LongAdder adder) {
        return adder == null ? 0L : adder.sum();
    }

    private static double sum(DoubleAdder adder) {
        return adder == null ? 0.0 : adder.sum();
    }

    private static int size(Set<?> set) {
        return set == null ? 0 : set.size();
    }

    /**
     * Highest-count key in {@code counts}, or null if empty. Ties are
     * broken arbitrarily (whatever {@code ConcurrentHashMap} iterates
     * first with the max value) - there's no meaningful tie-break rule
     * for "which repo is more active" when two are exactly equal.
     */
    private static String topEntry(Map<String, LongAdder> counts) {
        String top = null;
        long max = -1;
        for (Map.Entry<String, LongAdder> entry : counts.entrySet()) {
            long value = entry.getValue().sum();
            if (value > max) {
                max = value;
                top = entry.getKey();
            }
        }
        return top;
    }

    /** Mutable per-session running totals; only ever touched via computeIfAbsent + update. */
    private static final class SessionAcc {
        final String repoName;
        volatile Instant firstEventAt;
        volatile Instant lastEventAt;
        final LongAdder promptCount = new LongAdder();
        final DoubleAdder costUsd = new DoubleAdder();

        SessionAcc(String repoName, Instant firstEventAt) {
            this.repoName = repoName;
            this.firstEventAt = firstEventAt;
            this.lastEventAt = firstEventAt;
        }

        synchronized void update(Instant timestamp, boolean isPrompt, double cost) {
            if (timestamp.isBefore(firstEventAt)) {
                firstEventAt = timestamp;
            }
            if (timestamp.isAfter(lastEventAt)) {
                lastEventAt = timestamp;
            }
            if (isPrompt) {
                promptCount.increment();
            }
            costUsd.add(cost);
        }
    }
}