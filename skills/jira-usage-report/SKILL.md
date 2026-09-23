---
name: jira-usage-report
description: Cross-references a JIRA ticket's status history against actual Claude Code usage recorded in OpenObserve - hours used, cost in USD, and whether the ticket finished faster or slower than its story-point estimate. Use whenever someone asks how much Claude was used on a JIRA ticket, whether it saved time, what it cost, or asks for a usage/cost report across several tickets.
---

# JIRA usage report

Runs `jira-usage-report.ps1` (bundled in this skill's own folder) to cross-reference a JIRA ticket's real status history against actual Claude Code usage recorded in an OpenObserve instance fed by `claude-history-ingestor`.

## When to use this

- "How much did I use Claude on GGLOBDRA-1900?"
- "Did I save time using Claude on this ticket?"
- "What did GGLOBDRA-1900 cost in Claude usage?"
- A usage/cost report is wanted across a list of tickets

## Before running it

Five values are needed - `JiraBase`, `JiraUser`, `JiraToken`, `OpenObserveUser`, `OpenObservePassword`. They default from environment variables (`JIRA_BASE`, `JIRA_USER`, `JIRA_TOKEN`, `OPENOBSERVE_USER`, `OPENOBSERVE_PASSWORD`) if already set in the session. `OpenObserveUrl` defaults from `OPENOBSERVE_URL` (falling back to `http://localhost:5080`) - on Podman/WSL machines it's often a WSL IP instead, so don't assume localhost. The repo's `setEnvironment.ps1` sets all of these in `$PROFILE`. The script checks JIRA credentials up front and stops with a clear "JIRA auth failed" message if the token is rejected - relay that fix-up advice rather than retrying. If any are missing, **ask the person for them rather than guessing or inventing placeholder values** - and suggest adding them to their PowerShell profile (`$PROFILE`) so this only needs doing once, ever, not per session.

## Running it

```powershell
# One ticket
<skill-folder>\jira-usage-report.ps1 -Ticket "GGLOBDRA-1900"

# Several tickets
<skill-folder>\jira-usage-report.ps1 -Tickets "GGLOBDRA-1900","GGLOBDRA-1901"

# A longer list from a file (one ticket key per line)
<skill-folder>\jira-usage-report.ps1 -TicketsFile .\tickets.txt
```

**Important:** invoke the `.ps1` file directly - never wrap it in `powershell -File ...`. That wrapper spawns a separate child process and re-serializes arguments onto its command line, which has a confirmed bug: passing `-Tickets` with multiple values through it silently keeps only the last one, with no error. If the script has never been run on this machine before, run `Unblock-File -Path <path-to-script>` once first (removes Windows' "downloaded from the internet" flag) - otherwise there's a one-time interactive security prompt.

## Reading the result

Report back plainly, not the whole raw table: `ActualDays` vs. the story-point range, `Total Cost USD`, `Claude Usage %`, and `Days Saved`/`Saved %` if present. Full detail (every column, every repo touched) is always written to `claude-report.csv` in the current directory (override with `-OutputCsv`) regardless - mention that it's there rather than reproducing the whole thing inline.

**Two things worth surfacing if they come up, not just silently passed through:**
- `Verdict: unmapped` means the ticket's story-point value has no entry in `story-points.yaml` (bundled alongside this script) - not an error, just nothing to compare against.
- `Days Saved`/`Saved %` measures *elapsed calendar time* (In Progress → Under Review) against the story-point estimate - it has no connection to actual Claude usage hours or cost. A ticket can show a large "time saved" while barely using Claude, or vice versa. Don't conflate the two when reporting back.

## Configuration

`story-points.yaml`, alongside this script, maps story points to an expected day range (e.g. `3` → `3-5 days`). Edit it directly if the team's own estimation calibration differs from whatever's currently in it - it's a plain reference table, not derived from data.
