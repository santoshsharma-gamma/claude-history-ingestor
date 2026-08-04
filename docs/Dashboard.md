# Dashboard SQL — `claude_code_history` stream

Ready-to-paste SQL for building OpenObserve dashboard panels against the
stream this app ships events to. Each query is meant to back one panel
(Dashboards → New Dashboard → Add Panel → paste the SQL, pick a chart
type).

## Start here: a minimal 5-panel dashboard

After a lot of ad-hoc exploration in this project's history, these five
panels are the actual recommended starting point - everything else below
is reference material for when you need something more specific. All
five deliberately use `event_type IN ('USER', 'ASSISTANT')`, excluding
the still-unexplained `UNKNOWN` event type (currently ~38% of one real
deployment's data) from cost/token totals, so headline numbers aren't
silently inflated or distorted by data nobody's root-caused yet.

**Field name note:** the rest of this doc (below this section) was
written assuming a `llm_cost_usd` field (a plain dollar value). What's
actually live in at least one real deployment is `llm_cost_usd_micros`
(an integer in micro-dollars - divide by 1,000,000 to get dollars). This
points to the running code having diverged from what's been provided in
this conversation - worth reconciling at some point, but not blocking
right now. The five queries below use the field name confirmed to
actually exist (`llm_cost_usd_micros`); if your schema instead has
`llm_cost_usd`, drop the `/ 1000000.0` conversions.

**1. Headline KPIs** (single-row panel):

```sql
SELECT
  count(distinct repo_name) AS active_projects,
  count(distinct code_git_branch) AS active_branches,
  sum(CASE WHEN event_type = 'USER' THEN 1 ELSE 0 END) AS user_events,
  round(sum(llm_cost_usd_micros) / 1000000.0, 2) AS total_cost_usd,
  round(sum(llm_usage_input_tokens + llm_usage_output_tokens) / 1000000.0, 2) AS total_tokens_millions
FROM claude_code_history
WHERE event_type IN ('USER', 'ASSISTANT')
```

**2. Top 10 projects by cost and time** (bar chart):

```sql
SELECT
  repo_name,
  count(*) AS events,
  round(sum(duration_seconds) / 3600.0, 1) AS hours,
  round(sum(session_cost_micros) / 1000000.0, 2) AS cost_usd
FROM (
  SELECT session_id, repo_name,
    (max(_timestamp) - min(_timestamp)) / 1000000.0 AS duration_seconds,
    sum(llm_cost_usd_micros) AS session_cost_micros
  FROM claude_code_history
  WHERE repo_name IS NOT NULL AND event_type IN ('USER', 'ASSISTANT')
  GROUP BY session_id, repo_name
)
GROUP BY repo_name
ORDER BY cost_usd DESC
LIMIT 10
```

**3. Cost trend, monthly** (line chart):

```sql
SELECT
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  round(sum(llm_cost_usd_micros) / 1000000.0, 2) AS cost_usd
FROM claude_code_history
WHERE event_type IN ('USER', 'ASSISTANT')
GROUP BY month
ORDER BY month
```

**4. Top 10 JIRA tickets by cost** (table):

```sql
SELECT jira_ticket, repo_name, count(*) AS events, round(sum(cost_micros) / 1000000.0, 2) AS cost_usd
FROM (
  SELECT repo_name, llm_cost_usd_micros AS cost_micros,
    CASE WHEN re_match(code_git_branch, '[A-Z][A-Z0-9]+-[0-9]+')
      THEN regexp_replace(code_git_branch, '.*?([A-Z][A-Z0-9]+-[0-9]+).*', '$1')
      ELSE NULL END AS jira_ticket
  FROM claude_code_history
  WHERE code_git_branch IS NOT NULL AND event_type IN ('USER', 'ASSISTANT')
)
WHERE jira_ticket IS NOT NULL
GROUP BY jira_ticket, repo_name
ORDER BY cost_usd DESC
LIMIT 10
```

**5. Data-completeness callout** (keep visible, don't hide it):

```sql
SELECT event_type, count(*) AS events FROM claude_code_history GROUP BY event_type
```

Worth a text note alongside this panel: *"UNKNOWN event types are
excluded from the totals above until root-caused."* Once that
investigation lands, `EventType.fromRaw()` may need a new case added,
and this panel should be revisited.

**Standing decision:** use `event_type = 'USER'` as the definition of
"user interaction" throughout - not `event_is_prompt`. This does mean
automatic `tool_result` feedback gets counted alongside things actually
typed, but it's the simpler, currently-working option, and that's the
call that's been made for now.

---

## Field names: dots become underscores

This project's OTLP attributes use dots (`event.type`, `llm.cost_usd`,
`repo.name`, ...) — that's the OpenTelemetry semantic-conventions style,
and what `ClaudeEventToLogRecordMapper` emits. **OpenObserve normalizes
dots to underscores at ingest time**, per OpenObserve's own documentation
on this exact behavior. So in SQL, `event.type` is `event_type`,
`llm.cost_usd` is `llm_cost_usd`, and so on. Every query below already
uses the underscore form — if a query returns "field not found," check
the stream's schema in the OpenObserve UI (Streams → `claude_code_history`
→ Schema) to confirm the exact name OpenObserve settled on for that
attribute, since this conversion is version-dependent behavior on
OpenObserve's side, not something this project controls.

## Two attributes that changed shape this phase

- **`llm_cost_usd`** is new as of Phase 10. It didn't exist before —
  `ClaudeEventToLogRecordMapper` only gained a `CostCalculator` dependency
  this phase specifically so a "cost over time" panel would have
  something to query. Only present on events with a `message` (i.e.
  assistant turns); absent (not zero) on others.
- **`repo_technologies`** changed from a comma-joined string
  (`"Java (Maven),Terraform"`) to a stringified JSON array
  (`["Java (Maven)","Terraform"]`). OpenObserve's array functions
  (`cast_to_arr`, `unnest`) only operate on the JSON-array shape, not a
  plain comma-joined string — this was the "concrete query that needs it"
  moment flagged as a known simplification back in Phase 7.
- **`event_is_prompt`** is new post-Phase-11, added when it became clear
  there was no way to distinguish an actual typed user message from an
  automatic `tool_result` being fed back, using only what was already in
  the stream. Uses the exact same `PromptClassifier` logic the app's own
  analytics engine (Phase 8) already applied internally for its "today's
  prompts" metric — so this and `GET /analytics/daily` now agree on what
  counts as a prompt, rather than the dashboard needing to guess at its
  own definition.
- **`code_jira_ticket`** is new post-Phase-11: extracted from
  `code_git_branch` (e.g. `feature/GGLOBDRA-1813-provisioning-s3-bucket`
  → `GGLOBDRA-1813`) so a dashboard can group by ticket without
  re-deriving this in every query. Added at the source in Java rather
  than attempted in SQL, since OpenObserve's own documented custom SQL
  functions (`re_match`/`re_not_match`) are boolean filters only, not
  extractors — and I couldn't confirm standard DataFusion extraction
  functions (`regexp_replace`/`regexp_match`) are exposed through
  OpenObserve's SQL layer specifically. Null when the branch name doesn't
  contain something ticket-shaped (`main`, `HEAD`, `release/2.1.220`, etc.
  all correctly yield null, not a false match).

---

## Events over time

```sql
SELECT histogram(_timestamp) AS time, count(*) AS events
FROM claude_code_history
GROUP BY time
ORDER BY time
```

## Events by type

```sql
SELECT event_type, count(*) AS events
FROM claude_code_history
GROUP BY event_type
ORDER BY events DESC
```

## Top tools used

```sql
SELECT tool_name, count(*) AS uses
FROM claude_code_history
WHERE tool_name IS NOT NULL
GROUP BY tool_name
ORDER BY uses DESC
LIMIT 20
```

## Token usage over time (stacked)

```sql
SELECT histogram(_timestamp) AS time,
       sum(llm_usage_input_tokens) AS input_tokens,
       sum(llm_usage_output_tokens) AS output_tokens
FROM claude_code_history
GROUP BY time
ORDER BY time
```

## Cost over time

```sql
SELECT histogram(_timestamp) AS time, sum(llm_cost_usd) AS cost_usd
FROM claude_code_history
WHERE llm_cost_usd IS NOT NULL
GROUP BY time
ORDER BY time
```

## Error rate over time

```sql
SELECT histogram(_timestamp) AS time,
       count(*) AS total_events,
       sum(CASE WHEN event_is_error = true THEN 1 ELSE 0 END) AS errors
FROM claude_code_history
GROUP BY time
ORDER BY time
```

(Compute the rate as `errors / total_events` in the dashboard panel's
value formatting, or in a wrapping query — kept as two raw counts here
since dividing inside SQL breaks if `total_events` is ever 0 for a
bucket.)

## Sessions timeline

```sql
SELECT session_id,
       repo_name,
       min(_timestamp) AS started_at,
       max(_timestamp) AS ended_at,
       count(*) AS events
FROM claude_code_history
GROUP BY session_id, repo_name
ORDER BY started_at DESC
LIMIT 50
```

## Repository activity breakdown

```sql
SELECT repo_name,
       count(*) AS events,
       sum(llm_cost_usd) AS cost_usd,
       max(_timestamp) AS last_active_at
FROM claude_code_history
WHERE repo_name IS NOT NULL
GROUP BY repo_name
ORDER BY events DESC
```

## Top languages / technologies

Needs `cast_to_arr` + `unnest` since `repo_technologies` is a stringified
JSON array, not a native array column:

```sql
SELECT technology, count(*) AS events
FROM (
  SELECT unnest(cast_to_arr(repo_technologies)) AS technology
  FROM claude_code_history
  WHERE repo_technologies IS NOT NULL
)
GROUP BY technology
ORDER BY events DESC
```

## Most expensive individual exchanges

```sql
SELECT _timestamp, session_id, repo_name, llm_model, llm_cost_usd, body
FROM claude_code_history
WHERE llm_cost_usd IS NOT NULL
ORDER BY llm_cost_usd DESC
LIMIT 20
```

## Model usage breakdown

```sql
SELECT llm_model,
       count(*) AS events,
       sum(llm_usage_input_tokens) AS input_tokens,
       sum(llm_usage_output_tokens) AS output_tokens,
       sum(llm_cost_usd) AS cost_usd
FROM claude_code_history
WHERE llm_model IS NOT NULL
GROUP BY llm_model
ORDER BY cost_usd DESC
```

## Usage by project, month-wise

`histogram()` (used everywhere above) only supports fixed-duration
buckets like `'1 hour'` or `'1 day'` - months vary in length, so it can't
bucket by calendar month. This uses `date_trunc`, which OpenObserve's
underlying query engine (Apache DataFusion) supports directly, once the
raw microsecond `_timestamp` is converted with `to_timestamp_micros`.
Not run against a live instance while writing this - worth confirming it
works in your OpenObserve version before relying on it; the `EXTRACT`-based
fallback below is the thing to try if `date_trunc` errors.

One project, month-wise:

```sql
SELECT
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  count(*) AS events,
  sum(llm_usage_input_tokens) AS input_tokens,
  sum(llm_usage_output_tokens) AS output_tokens,
  sum(llm_cost_usd) AS cost_usd
FROM claude_code_history
WHERE repo_name = 'asset-search'   -- swap for your project's repo_name
GROUP BY month
ORDER BY month
```

All projects side by side, month-wise:

```sql
SELECT
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  repo_name,
  count(*) AS events,
  sum(llm_usage_input_tokens) AS input_tokens,
  sum(llm_usage_output_tokens) AS output_tokens,
  sum(llm_cost_usd) AS cost_usd
FROM claude_code_history
WHERE repo_name IS NOT NULL
GROUP BY month, repo_name
ORDER BY month, cost_usd DESC
```

Fallback if `date_trunc`/`to_timestamp_micros` isn't available in your
OpenObserve version:

```sql
SELECT
  EXTRACT(year FROM to_timestamp_micros(_timestamp)) AS year,
  EXTRACT(month FROM to_timestamp_micros(_timestamp)) AS month,
  repo_name,
  count(*) AS events,
  sum(llm_cost_usd) AS cost_usd
FROM claude_code_history
WHERE repo_name = 'asset-search'
GROUP BY year, month, repo_name
ORDER BY year, month
```

## Time spent per project, month-wise

There's no duration field in the stream - this derives it as
`max(_timestamp) - min(_timestamp)` per session, then sums that across
sessions per project per month. Three things worth knowing about this
definition before trusting the numbers:

- A session with only a single recorded event shows **0 duration**
  (start equals end) - this systematically undercounts very short
  sessions, it doesn't just round them down.
- A session that happens to straddle a calendar-month boundary has its
  *entire* duration attributed to the month of its first event, not
  split across both months.
- This measures wall-clock time between first and last event, including
  any idle gaps in between - not continuous active engagement. That
  matches how the app's own `SessionSummary` (Phase 8's
  `MetricsAccumulator`, exposed via `GET /analytics/activity`) already
  defines session duration, so at least it's consistent with what the
  app reports about itself elsewhere.

All projects, month-wise:

```sql
SELECT
  repo_name,
  date_trunc('month', to_timestamp_micros(session_start_us)) AS month,
  count(*) AS sessions,
  round(sum(duration_seconds) / 3600.0, 2) AS total_hours
FROM (
  SELECT
    session_id,
    repo_name,
    min(_timestamp) AS session_start_us,
    (max(_timestamp) - min(_timestamp)) / 1000000.0 AS duration_seconds
  FROM claude_code_history
  WHERE repo_name IS NOT NULL AND session_id IS NOT NULL
  GROUP BY session_id, repo_name
)
GROUP BY repo_name, month
ORDER BY month, total_hours DESC
```

One project, month-wise: add `AND repo_name = 'asset-search'` to the
inner query's `WHERE` clause.

## Days used and total hours, per project + branch

Two different questions worth keeping separate rather than combining
into one query: how many distinct calendar days had any activity at all
(simple, robust), versus total session duration in hours (uses the same
derivation and caveats as "Time spent per project" above - a
single-event session shows 0 duration, and this counts wall-clock time
including idle gaps, not active typing time).

Days used:

```sql
SELECT
  repo_name,
  code_git_branch,
  count(distinct date_trunc('day', to_timestamp_micros(_timestamp))) AS days_used,
  sum(llm_usage_input_tokens) AS input_tokens,
  sum(llm_usage_output_tokens) AS output_tokens,
  sum(llm_usage_input_tokens) + sum(llm_usage_output_tokens) AS total_tokens
FROM claude_code_history
WHERE repo_name IS NOT NULL
GROUP BY repo_name, code_git_branch
ORDER BY days_used DESC
```

Total hours:

```sql
SELECT
  repo_name,
  code_git_branch,
  count(*) AS sessions,
  round(sum(duration_seconds) / 3600.0, 2) AS total_hours,
  sum(input_tokens) AS input_tokens,
  sum(output_tokens) AS output_tokens,
  sum(input_tokens) + sum(output_tokens) AS total_tokens
FROM (
  SELECT
    session_id,
    repo_name,
    min(code_git_branch) AS code_git_branch,
    (max(_timestamp) - min(_timestamp)) / 1000000.0 AS duration_seconds,
    sum(llm_usage_input_tokens) AS input_tokens,
    sum(llm_usage_output_tokens) AS output_tokens
  FROM claude_code_history
  WHERE repo_name IS NOT NULL
  GROUP BY session_id, repo_name
)
GROUP BY repo_name, code_git_branch
ORDER BY total_hours DESC
```

`min(code_git_branch)` picks *a* branch per session (whichever sorts
alphabetically first) - fine when a session stays on one branch
throughout, which is the common case, but worth knowing about if a
session ever switches branches mid-way.

## Real user prompts only, by project, month-wise

Everything above counts every event - including automatic `tool_result`
records that were never actually typed by a person. Filtering on
`event_is_prompt = true` (see the attributes note above) gets just the
actual interactions:

```sql
SELECT
  repo_name,
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  count(*) AS prompts
FROM claude_code_history
WHERE event_is_prompt = true
  AND repo_name IS NOT NULL
GROUP BY repo_name, month
ORDER BY month, prompts DESC
```

One project, month-wise: add `AND repo_name = 'asset-search'`.

With git branch broken out too (`code_git_branch` is already exported -
see `ClaudeEvent.gitBranch()` via Phase 5's model):

```sql
SELECT
  repo_name,
  code_git_branch,
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  count(*) AS prompts
FROM claude_code_history
WHERE event_is_prompt = true
  AND repo_name IS NOT NULL
GROUP BY repo_name, code_git_branch, month
ORDER BY month, prompts DESC
```

### Simpler alternative: `event_type = 'USER'` instead of `event_is_prompt`

If `event_is_prompt` isn't showing up yet (e.g. only old, pre-fix data
has been ingested so far - see the README's post-Phase-11 addendum),
`event_type = 'USER'` works as an approximation:

```sql
SELECT
  repo_name,
  code_git_branch,
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  count(*) AS events
FROM claude_code_history
WHERE event_type = 'USER'
  AND repo_name IS NOT NULL
GROUP BY repo_name, code_git_branch, month
ORDER BY month, events DESC
```

**The tradeoff to know about:** this counts every `USER`-type record,
including automatic `tool_result` feedback (e.g. "file updated
successfully" messages Claude Code generates after a tool call) - not
just things actually typed by a person. `event_is_prompt = true` is the
precise version; `event_type = 'USER'` is the simpler fallback that
overcounts by including that automatic feedback.

## Activity by JIRA ticket

Uses the new `code_jira_ticket` field (see the attributes note above) -
extracted from `code_git_branch`, so this groups cleanly even though the
underlying branch names vary (`feature/GGLOBDRA-1813-x`,
`bugfix/GGLOBDRA-1813-y`, etc. all collapse to the same ticket):

```sql
SELECT
  code_jira_ticket,
  repo_name,
  count(*) AS events,
  sum(llm_cost_usd) AS cost_usd
FROM claude_code_history
WHERE code_jira_ticket IS NOT NULL
GROUP BY code_jira_ticket, repo_name
ORDER BY events DESC
```

### SQL-only alternative (no app rebuild needed)

If `code_jira_ticket` isn't showing up yet (the app-side fix requires a
rebuild - see the README's post-Phase-11 addendum), the same extraction
can be done directly in SQL using `regexp_replace` and `re_match` -
confirmed available per OpenObserve's own documentation ("OpenObserve
uses Apache DataFusion as its query engine. All supported SQL syntax and
functions are available through DataFusion."). One important syntax
note: DataFusion's `regexp_replace` is Rust-based and uses `$1` for
backreferences in the replacement string, not `\1`.

```sql
SELECT
  repo_name,
  code_git_branch,
  jira_ticket,
  count(*) AS events,
  sum(llm_usage_input_tokens) AS input_tokens,
  sum(llm_usage_output_tokens) AS output_tokens,
  sum(llm_cost_usd) AS cost_usd
FROM (
  SELECT
    repo_name,
    code_git_branch,
    llm_usage_input_tokens,
    llm_usage_output_tokens,
    llm_cost_usd,
    CASE
      WHEN re_match(code_git_branch, '[A-Z][A-Z0-9]+-[0-9]+')
      THEN regexp_replace(code_git_branch, '.*?([A-Z][A-Z0-9]+-[0-9]+).*', '$1')
      ELSE NULL
    END AS jira_ticket
  FROM claude_code_history
  WHERE code_git_branch IS NOT NULL
)
GROUP BY repo_name, code_git_branch, jira_ticket
ORDER BY events DESC
```

### Filtered to specific tickets, by month

The `jira_ticket IN (...)` filter has to go in the *outer* query, not the
inner one - the inner subquery is what computes `jira_ticket` in the
first place, so it isn't available to filter on until one level up:

```sql
SELECT
  jira_ticket,
  code_git_branch,
  date_trunc('month', to_timestamp_micros(_timestamp)) AS month,
  count(*) AS events,
  sum(llm_usage_input_tokens) AS input_tokens,
  sum(llm_usage_output_tokens) AS output_tokens
FROM (
  SELECT
    _timestamp,
    repo_name,
    code_git_branch,
    llm_usage_input_tokens,
    llm_usage_output_tokens,
    CASE
      WHEN re_match(code_git_branch, '[A-Z][A-Z0-9]+-[0-9]+')
      THEN regexp_replace(code_git_branch, '.*?([A-Z][A-Z0-9]+-[0-9]+).*', '$1')
      ELSE NULL
    END AS jira_ticket
  FROM claude_code_history
  WHERE code_git_branch IS NOT NULL
)
WHERE jira_ticket IN ('GGLOBDRA-1813', 'GGLOBDRA-1958')
GROUP BY jira_ticket, code_git_branch, month
ORDER BY jira_ticket, month
```

Swap in your actual ticket list. For day-level instead of month-level,
change `'month'` to `'day'` in `date_trunc` - nothing else needs to change.