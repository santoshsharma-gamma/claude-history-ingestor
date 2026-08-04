# jira-usage-report.ps1 — field reference

What each column in the console report actually measures, and how it's
calculated. Written for explaining to the team, not just for reference.

## The active columns

| Column | What it is |
|---|---|
| `Ticket` | JIRA ticket key |
| `Repo` | A repository touched during the ticket's work |
| `PromptsAsked` | Count of real, typed questions |
| `Total Tokens` | Full token volume (input + output + cache) |
| `Total Hrs Actual Work` | Real Claude session time |
| `Total Cost USD` | Real Claude session cost, in USD |
| `Hrs Saved` | Estimated hours saved vs. story-point estimate |
| `Story Point Saved` | The same saving, expressed in story points |

## Two important structural things to know before reading the numbers

**1. `PromptsAsked` and `Total Hrs Actual Work`/`Total Cost USD`/`Hrs
Saved`/`Story Point Saved` are ticket-level totals - the SAME number
repeats on every repo row for that ticket.** Only `Total Tokens` genuinely
varies per repo. **Don't sum these ticket-level columns across a
ticket's multiple repo rows** - that would multiply the real total by
however many repos the ticket touched. Sum `Total Tokens` across repos
if you want a ticket's total token count; the other repeated columns
are already the ticket's total, once.

**2. `PromptsAsked` is NOT scoped to the same time window as the other
fields.** It matches every real prompt ever recorded against the
ticket's branch pattern (JIRA key found in `code_git_branch`), with no
time bound. Everything else (`Total Hrs Actual Work`, `Total Cost USD`,
`Hrs Saved`, `Story Point Saved`) is scoped specifically to the ticket's
JIRA lifecycle (In Progress → Under Review → Closed). In practice this
rarely matters, but it means `PromptsAsked` could technically include a
prompt from before the ticket was marked "In Progress," if the branch
existed and was used earlier.

## The calculations

### PromptsAsked
Count of events where `event_is_prompt = true`, matching
`code_git_branch LIKE '%TICKET-KEY%'`. Not the same as a raw event
count - a single typed prompt can trigger many automated tool
calls/results afterward, none of which count here.

### Total Tokens
```
Total Tokens = input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens
```
All four, summed per session within the ticket's In-Progress-to-Closed
(or -to-now, if still open) window, then summed again across sessions
for that repo. Cache tokens are included deliberately - on a long
agentic session they can be the majority of total volume, and leaving
them out (as an earlier version of this report did) makes the number
look inconsistent with the actual cost.

### Total Hrs Actual Work
```
Total Hrs Actual Work = ClaudeHoursBeforeReview + ClaudeHoursDuringReview
```
Real Claude session time (first-to-last event per session, summed),
split into before the ticket moved to "Under Review" and after, then
added back together. Blank (not zero) if the ticket has never reached
"Under Review" at all - there's nothing to split yet, not a genuine
zero.

### Total Cost USD
Same structure as `Total Hrs Actual Work`, in dollars instead of hours -
`CostBeforeReview + CostDuringReview`, each pulled from
`llm_cost_usd` (a string field, cast to double for summing).

### Hrs Saved
```
ActualDaysToReview = (Under-Review timestamp − In-Progress timestamp) ÷ 24
DaysSaved  = ExpectedMinDays − ActualDaysToReview   (0 if this isn't positive)
Hrs Saved  = DaysSaved × 8   (configurable via -HoursPerDay)
```
`ExpectedMinDays` comes from `story-points.yaml`, keyed by the ticket's
story-point value (e.g. 5 points → 5 minimum expected days).

**This is purely elapsed calendar time - it has no connection to Claude
usage hours or cost at all.** A ticket can show a large "Hrs Saved"
while barely using Claude, or the reverse. Don't read this as "hours of
work Claude saved" - it's "did the ticket reach review faster than the
team's own estimate."

### Story Point Saved
```
Story Point Saved = DaysSaved × (StoryPoints ÷ ExpectedMinDays)
```
Not just `DaysSaved` relabeled - a real unit conversion. It happens to
equal `DaysSaved` numerically today because every entry in
`story-points.yaml` sets `min-days` equal to the point value itself (5
points → min-days: 5, 8 points → min-days: 8). If that mapping is ever
reconfigured so those diverge, this still converts correctly.

## What none of this proves

Every "saved" figure here is a comparison between actual elapsed time
and the team's own estimate, during a period when Claude was used - not
a measurement of Claude causing the difference. There's no
counterfactual (the same ticket completed without Claude) to compare
against. Useful as a signal, not as proof.
