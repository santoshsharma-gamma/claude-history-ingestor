<#
.SYNOPSIS
    Cross-references JIRA ticket status history against actual Claude
    Code usage in OpenObserve. Works for one ticket or many - combines
    what were previously two separate scripts (verify-jira-ticket.ps1
    and report-jira-tickets.ps1) into one.

.PARAMETER Ticket
    A single JIRA ticket key, e.g. GGLOBDRA-1813. Use this OR -Tickets
    OR -TicketsFile, not more than one.

.PARAMETER Tickets
    Array of ticket keys, e.g. -Tickets "GGLOBDRA-1813","GGLOBDRA-1958".

.PARAMETER TicketsFile
    Path to a text file with one ticket key per line.

.PARAMETER InProgressStatus / DoneStatus
    Your workflow's actual status names for "started" / "finished".
    Defaults to "In Progress" / "Closed" - check the printed transition
    table if these don't match your workflow and re-run with the right
    values.

.PARAMETER StoryPointMappingPath
    Path to a YAML file mapping story points to an expected duration
    range in days - see story-points.yaml alongside this script for the
    format. Defaults to .\story-points.yaml. If the file is missing, or
    a ticket's story point value has no entry in it, the expected-days
    comparison is simply skipped for that ticket (not an error).

.PARAMETER HoursPerDay
    Working hours per day, used only to convert DaysSaved into
    HoursSaved. Defaults to 8.

.PARAMETER OutputCsv
    Where to write the combined report. Defaults to
    jira-usage-report.csv in the current directory. Written even for a
    single ticket, so every run leaves a record behind.

.NOTES ON THE OverlapPct / InProgressOverlapPct / ClaudeHours COLUMNS
    Neither percentage measures "how much of the task Claude did" -
    both are proxies for calendar-time overlap, not effort share or
    code-authorship share. Two versions are reported because neither
    alone is reliable, and comparing them tells you something real:

    - OverlapPct = ClaudeHours / LifecycleHours * 100 (full ticket span,
      Open through Closed). Tends to UNDERSTATE usage when a ticket sat
      idle for a while (e.g. briefly bounced back to "Open", or spent
      real time waiting for review) before/after the actual work.

    - InProgressOverlapPct = ClaudeHours / cumulative-"In Progress"-time
      * 100. Narrower and usually more representative of the active
      coding window - but can UNDERSTATE too, or even exceed 100%, if
      real work happened during a review/wait status. This isn't
      hypothetical: on one real ticket (GGLOBDRA-1755), Claude usage
      during "Under Review" pushed total usage above the ticket's pure
      "In Progress" time. If you see InProgressOverlapPct near or above
      100%, that's the likely explanation, not a bug.

    Neither field substitutes for a real "share of the code Claude
    wrote" measurement, which would need comparing Claude's actual
    Edit/Write/MultiEdit diffs against the ticket's true total diff size
    from git/the PR - not something this script does today.

.NOTES ON StoryPoints / ExpectedMinDays / ExpectedMaxDays / Verdict
    Verdict is "under" (finished faster than the mapped range), "within"
    (inside it), "over" (took longer), or "unmapped" (no entry in
    story-points.yaml for that point value - not an error, just nothing
    to compare against). Worth reading the assumptions behind this
    before trusting it for anything that matters:

    1. The mapping (story-points.yaml) is a reference table you define,
       not something derived from your team's actual history - it's
       only as accurate as the ranges you put in it.
    2. "Actual days" = LifecycleHours / 24 = raw elapsed calendar time
       from first "In Progress" to Closed - includes weekends,
       holidays, and any idle stretches (like GGLOBDRA-1755's week back
       in "Open"), not just active working time.
    3. Attributing a ticket landing "under" its range specifically to
       Claude is an assumption, not a measurement - there's no
       counterfactual (the same ticket completed without Claude) to
       compare against. Best read as "actual vs. your team's own
       estimate range, during a period when Claude was used" rather
       than proven causation.

.NOTES ON TotalClaudeHours / TotalUsagePct / TotalCostUsd
    TotalClaudeHours = ClaudeHoursBeforeReview + ClaudeHoursDuringReview -
    real Claude session time across both phases, covering the case where
    a reviewer asks for changes and Claude is used again afterward, not
    just the initial build. TotalUsagePct is that total against the full
    ticket lifecycle. TotalCostUsd is the same before+during sum, in USD.
    All three are blank (not zero) if no "Under Review" transition was
    found - there's nothing to sum in that case, which is different from
    a genuine zero.

.NOTES ON DaysSaved / PctSaved
    IMPORTANT: this does NOT factor in Claude usage hours at all - it's
    purely elapsed CALENDAR time ("In Progress" to "Under Review")
    compared against the story-point estimate. It has no connection to
    TotalClaudeHours/TotalUsagePct/ClaudeHoursDuringReview - a ticket
    could show a large Saved% while barely using Claude, or a small one
    despite heavy use. Treat them as two separate questions ("did it
    finish faster than estimated" vs. "how much was Claude actually
    used"), not one combined metric.

    DaysSaved = ExpectedMinDays - (actual "In Progress" to "Under Review"
    days), and only when that's positive - 0 (not negative) if the
    fastest-case estimate wasn't beaten. Deliberately uses ExpectedMinDays
    specifically, not the midpoint or max of the range: if you beat the
    FASTEST-case estimate, that's a guaranteed minimum saving regardless
    of where the true estimate actually sat in the range - this never
    overstates the saving. PctSaved = DaysSaved / ExpectedMinDays * 100.

    Same causation caveat as everything else here: this shows the gap
    between actual time and your team's own estimate, during a period
    Claude was used - not proof Claude caused the difference.

    HoursSaved = DaysSaved * -HoursPerDay (default 8) - a plain unit
    conversion, nothing more.

    StoryPointsSaved is NOT just DaysSaved relabeled - it's
    DaysSaved * (StoryPoints / ExpectedMinDays), which only reduces to
    the same number as DaysSaved because the shipped story-points.yaml
    happens to set every entry's min-days equal to its point value (5 ->
    min-days 5, 8 -> min-days 8, etc). If that mapping is ever
    reconfigured so min-days and the point value diverge, this still
    converts correctly - DaysSaved alone would not.

.EXAMPLE
    # Set these once per session (or add to your PowerShell profile so
    # they persist across sessions) - see docs/jira-ticket-verification.md
    $env:JIRA_BASE = "https://your-domain.atlassian.net"
    $env:JIRA_USER = "you@company.com"
    $env:JIRA_TOKEN = "your-real-token"
    $env:OPENOBSERVE_USER = "root@example.com"
    $env:OPENOBSERVE_PASSWORD = "your-real-password"

    # Then every run is just this:
    .\jira-usage-report.ps1 -Ticket GGLOBDRA-1813

.EXAMPLE
    # A batch, from a file, into a named report (still just needs -Tickets/-TicketsFile
    # once the environment variables above are set)
    .\jira-usage-report.ps1 -TicketsFile .\tickets.txt -OutputCsv .\q3-report.csv

.EXAMPLE
    # Overriding a value just for one run still works normally
    .\jira-usage-report.ps1 -Ticket GGLOBDRA-1813 -OpenObserveUrl "http://otherhost:5080"

.NOTES
    Credentials are parameters/environment variables, never hardcoded -
    safe to keep this file in source control as-is.
#>

param(
    [string]$Ticket,
    [string[]]$Tickets,
    [string]$TicketsFile,

    [string]$InProgressStatus = "In Progress",
    [string]$DoneStatus = "Closed",
    [string]$ReviewStatus = "Under Review",

    [string]$JiraBase = $env:JIRA_BASE,
    [string]$JiraUser = $env:JIRA_USER,
    [string]$JiraToken = $env:JIRA_TOKEN,

    [string]$OpenObserveUrl = "http://localhost:5080",
    [string]$OpenObserveOrg = "default",
    [string]$OpenObserveUser = $env:OPENOBSERVE_USER,
    [string]$OpenObservePassword = $env:OPENOBSERVE_PASSWORD,

    [string]$StoryPointMappingPath = ".\story-points.yaml",
    [double]$HoursPerDay = 8,

    [string]$OutputCsv = ".\jira-usage-report.csv"
)

# Deliberately NOT [Parameter(Mandatory = $true)] on the credentials above -
# with Mandatory, PowerShell prompts interactively for anything missing,
# which is a confusing experience given these are meant to usually come
# from environment variables set once per session, not typed every run.
# Validating explicitly here instead gives a clear, actionable message.
$missingValues = @()
if (-not $JiraBase)             { $missingValues += "JiraBase (-JiraBase or `$env:JIRA_BASE)" }
if (-not $JiraUser)              { $missingValues += "JiraUser (-JiraUser or `$env:JIRA_USER)" }
if (-not $JiraToken)             { $missingValues += "JiraToken (-JiraToken or `$env:JIRA_TOKEN)" }
if (-not $OpenObserveUser)       { $missingValues += "OpenObserveUser (-OpenObserveUser or `$env:OPENOBSERVE_USER)" }
if (-not $OpenObservePassword)   { $missingValues += "OpenObservePassword (-OpenObservePassword or `$env:OPENOBSERVE_PASSWORD)" }
if ($missingValues.Count -gt 0) {
    Write-Host "Missing required value(s):"
    $missingValues | ForEach-Object { Write-Host "  - $_" }
    Write-Host "`nSet these once per PowerShell session (see docs/jira-ticket-verification.md), or pass them as flags."
    return
}

# --- Resolve the ticket list from whichever of -Ticket / -Tickets / -TicketsFile was given ---
if ($Ticket) {
    $TicketList = @($Ticket)
} elseif ($TicketsFile) {
    $TicketList = Get-Content $TicketsFile | Where-Object { $_.Trim() -ne "" }
} elseif ($Tickets) {
    $TicketList = $Tickets
} else {
    Write-Host "Provide one of: -Ticket, -Tickets, or -TicketsFile."
    return
}

# Always shown - if -Tickets was passed via `powershell -File ...` with
# comma-separated values, PowerShell's argument parsing in that mode
# doesn't reliably bind it as an array the way calling the script
# directly does; a comma can end up embedded in one string instead of
# separating two. This makes that visible immediately instead of a
# ticket silently vanishing from the report with no trace.
Write-Host "Processing $($TicketList.Count) ticket(s): $($TicketList -join ', ')`n"

$jiraPair    = "$JiraUser`:$JiraToken"
$jiraBase64  = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($jiraPair))
$jiraHeaders = @{ Authorization = "Basic $jiraBase64" }

$ooPair    = "$OpenObserveUser`:$OpenObservePassword"
$ooBase64  = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($ooPair))
$ooHeaders = @{ Authorization = "Basic $ooBase64"; "Content-Type" = "application/json" }

function Get-SafeSum {
    # Measure-Object -Property throws (a non-terminating error, so
    # try/catch doesn't catch it - it just prints an alarming message and
    # silently continues) if NONE of the input objects have that property
    # at all - which genuinely happens here: OpenObserve's schema-on-read
    # can omit a column entirely from a query's results when no matching
    # document in that specific time window has it populated, rather than
    # returning null/0 for it. This extracts manually instead, tolerating
    # a missing property as 0 rather than erroring.
    param($Objects, [string]$Property)
    $total = 0.0
    foreach ($obj in $Objects) {
        if ($obj.PSObject.Properties[$Property] -and $null -ne $obj.$Property) {
            $total += $obj.$Property
        }
    }
    return $total
}

function Get-CumulativeStatusDuration {
    # Sums every stretch the ticket spent in $Status, not just the first -
    # a ticket can bounce back to "Open" and re-enter "In Progress" more
    # than once (seen for real on GGLOBDRA-1755), and a naive
    # first-transition-to-last-transition window would misrepresent that.
    param($Transitions, [string]$Status, [DateTimeOffset]$Now)

    $total = [TimeSpan]::Zero
    for ($i = 0; $i -lt $Transitions.Count; $i++) {
        if ($Transitions[$i].To -eq $Status) {
            $stretchStart = $Transitions[$i].When
            $stretchEnd = if ($i + 1 -lt $Transitions.Count) { $Transitions[$i + 1].When } else { $Now }
            $total += ($stretchEnd - $stretchStart)
        }
    }
    return $total
}

function Get-StoryPointsFieldId {
    # Story Points is a custom field in JIRA - its actual field ID
    # (customfield_XXXXX) varies per JIRA site, so this resolves it by
    # display name rather than assuming a hardcoded ID. Different JIRA
    # setups call it "Story Points" or "Story point estimate" (JIRA
    # renamed this over time, and team-managed vs company-managed
    # projects can differ) - checks both.
    $fields = Invoke-RestMethod -Uri "$JiraBase/rest/api/3/field" -Headers $jiraHeaders -Method Get
    $match = $fields | Where-Object { $_.name -match "^Story Points?( estimate)?$" } | Select-Object -First 1
    return $match.id
}

function Get-StoryPoints {
    param([string]$TicketKey, [string]$FieldId)
    if (-not $FieldId) { return $null }
    $issue = Invoke-RestMethod -Uri "$JiraBase/rest/api/3/issue/$TicketKey`?fields=$FieldId" -Headers $jiraHeaders -Method Get
    return $issue.fields.$FieldId
}

function Get-StoryPointMapping {
    # Purpose-built parser for ONE specific shape - not a general YAML
    # parser. Only understands:
    #   story-points:
    #     "<number>":
    #       min-days: <number>
    #       max-days: <number>
    # (repeated for each story point value). Comments and blank lines
    # are ignored. Anything else in the file is silently skipped, not
    # validated - if a mapping doesn't show up, check its indentation
    # and key format match story-points.yaml's existing entries exactly.
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "Story point mapping file '$Path' not found - expected-days comparison will be skipped for all tickets.`n"
        return $null
    }

    $mapping = @{}
    $currentKey = $null
    $minDays = $null
    $maxDays = $null

    function Flush-Entry {
        if ($currentKey -and $null -ne $minDays -and $null -ne $maxDays) {
            $mapping[$currentKey] = @{ MinDays = $minDays; MaxDays = $maxDays }
        }
    }

    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*"?(\d+(\.\d+)?)"?\s*:\s*$') {
            Flush-Entry
            $currentKey = $matches[1]
            $minDays = $null
            $maxDays = $null
        } elseif ($line -match '^\s*min-days\s*:\s*(\d+(\.\d+)?)\s*$') {
            $minDays = [double]$matches[1]
        } elseif ($line -match '^\s*max-days\s*:\s*(\d+(\.\d+)?)\s*$') {
            $maxDays = [double]$matches[1]
        }
    }
    Flush-Entry
    return $mapping
}

function Resolve-StoryPointKey {
    # JIRA returns story points as a number that may look like "3.0" even
    # for a whole value - normalize to "3" so it matches a mapping key
    # like "3" rather than silently failing to match "3.0".
    param($StoryPoints)
    if ($StoryPoints -eq [Math]::Floor($StoryPoints)) {
        return "$([int]$StoryPoints)"
    }
    return "$StoryPoints"
}

function Get-JiraChangelog {
    param([string]$TicketKey)
    # Throws on failure - caller decides how to report it (single-ticket
    # detail view vs. a batch row), rather than this function guessing.
    return Invoke-RestMethod -Uri "$JiraBase/rest/api/3/issue/$TicketKey/changelog" -Headers $jiraHeaders -Method Get
}

function Get-StatusTransitions {
    param($Changelog)
    $transitions = @()
    foreach ($history in $Changelog.values) {
        foreach ($item in $history.items) {
            if ($item.field -eq "status") {
                $transitions += [PSCustomObject]@{
                    When = [DateTimeOffset]::Parse($history.created)
                    From = $item.fromString
                    To   = $item.toString
                }
            }
        }
    }
    return $transitions | Sort-Object When
}

function Get-PromptTexts {
    # Fetches the actual typed text of every real prompt on this ticket -
    # not just a count. Matches on the branch pattern directly (not a
    # time window), since prompt text is worth seeing regardless of which
    # phase (pre/during review) it happened in.
    param([string]$TicketKey)

    $sql = @"
SELECT _timestamp, repo_name, body
FROM claude_code_history
WHERE code_git_branch LIKE '%$TicketKey%'
  AND event_is_prompt = true
ORDER BY _timestamp
"@

    $body = @{
        query = @{
            sql        = $sql
            start_time = [DateTimeOffset]::UtcNow.AddYears(-2).ToUnixTimeMilliseconds() * 1000
            end_time   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000
            from       = 0
            size       = 100
        }
    } | ConvertTo-Json -Depth 5

    return Invoke-RestMethod -Uri "$OpenObserveUrl/api/$OpenObserveOrg/_search" -Headers $ooHeaders -Method Post -Body $body
}

function Get-UsageInWindow {
    param([string]$TicketKey, [DateTimeOffset]$Start, [DateTimeOffset]$End)

    # Note: computes per-session duration (not just event counts), so the
    # caller can derive a "% of ticket lifecycle with active Claude use"
    # figure - see the SYNOPSIS note on what that percentage does and
    # doesn't represent. llm_cost_usd is a STRING field (not a native
    # number) - see docs/dashboard-sql.md for why - hence the CAST.
    $sql = @"
SELECT jira_ticket, repo_name,
       count(*) AS sessions,
       sum(events) AS events,
       sum(input_tokens) AS input_tokens,
       sum(output_tokens) AS output_tokens,
       sum(cache_read_tokens) AS cache_read_tokens,
       sum(cache_creation_tokens) AS cache_creation_tokens,
       round(sum(duration_seconds) / 3600.0, 3) AS claude_hours,
       round(sum(cost_usd), 2) AS cost_usd
FROM (
  SELECT
    session_id, repo_name,
    count(*) AS events,
    sum(llm_usage_input_tokens) AS input_tokens,
    sum(llm_usage_output_tokens) AS output_tokens,
    sum(llm_usage_cache_read_input_tokens) AS cache_read_tokens,
    sum(llm_usage_cache_creation_input_tokens) AS cache_creation_tokens,
    (max(_timestamp) - min(_timestamp)) / 1000000.0 AS duration_seconds,
    sum(CAST(llm_cost_usd AS DOUBLE)) AS cost_usd,
    CASE WHEN re_match(min(code_git_branch), '[A-Z][A-Z0-9]+-[0-9]+')
      THEN regexp_replace(min(code_git_branch), '.*?([A-Z][A-Z0-9]+-[0-9]+).*', '`$1')
      ELSE NULL END AS jira_ticket
  FROM claude_code_history
  WHERE code_git_branch IS NOT NULL
  GROUP BY session_id, repo_name
)
WHERE jira_ticket = '$TicketKey'
GROUP BY jira_ticket, repo_name
"@

    $body = @{
        query = @{
            sql        = $sql
            start_time = $Start.ToUnixTimeMilliseconds() * 1000
            end_time   = $End.ToUnixTimeMilliseconds() * 1000
            from       = 0
            size       = 10
        }
    } | ConvertTo-Json -Depth 5

    return Invoke-RestMethod -Uri "$OpenObserveUrl/api/$OpenObserveOrg/_search" -Headers $ooHeaders -Method Post -Body $body
}

function New-ReportRow {
    param($TicketKey, $Repo = "", $InProgressAt = "", $ClosedAt = "", $Events = 0, $PromptsAsked = 0, $InputTokens = 0, $OutputTokens = 0,
          $CacheReadTokens = 0, $CacheCreationTokens = 0,
          $ClaudeHours = 0, $CostUsd = "", $LifecycleHours = 0, $OverlapPct = "", $InProgressHours = 0, $InProgressOverlapPct = "",
          $ReviewAt = "", $PreReviewHours = "", $ClaudeHoursBeforeReview = "", $PctUsedBeforeReview = "",
          $DuringReviewHours = "", $ClaudeHoursDuringReview = "", $TotalClaudeHours = "", $TotalUsagePct = "", $TotalCostUsd = "",
          $StoryPoints = "", $ExpectedMinDays = "", $ExpectedMaxDays = "", $ActualDays = "", $Verdict = "",
          $PreReviewDays = "", $DaysSaved = "", $PctSaved = "", $HoursSaved = "", $StoryPointsSaved = "", $Note = "")
    return [PSCustomObject]@{
        Ticket                  = $TicketKey
        Repo                    = $Repo
        InProgressAt            = $InProgressAt
        ClosedAt                = $ClosedAt
        Events                  = $Events
        PromptsAsked            = $PromptsAsked
        InputTokens             = $InputTokens
        OutputTokens            = $OutputTokens
        CacheReadTokens         = $CacheReadTokens
        CacheCreationTokens     = $CacheCreationTokens
        ClaudeHours             = $ClaudeHours
        CostUsd                 = $CostUsd
        LifecycleHours          = $LifecycleHours
        OverlapPct              = $OverlapPct
        InProgressHours         = $InProgressHours
        InProgressOverlapPct    = $InProgressOverlapPct
        ReviewAt                = $ReviewAt
        PreReviewHours          = $PreReviewHours
        PreReviewDays           = $PreReviewDays
        ClaudeHoursBeforeReview = $ClaudeHoursBeforeReview
        PctUsedBeforeReview     = $PctUsedBeforeReview
        DuringReviewHours       = $DuringReviewHours
        ClaudeHoursDuringReview = $ClaudeHoursDuringReview
        TotalClaudeHours        = $TotalClaudeHours
        TotalUsagePct           = $TotalUsagePct
        TotalCostUsd            = $TotalCostUsd
        StoryPoints             = $StoryPoints
        ExpectedMinDays         = $ExpectedMinDays
        ExpectedMaxDays         = $ExpectedMaxDays
        ActualDays              = $ActualDays
        Verdict                 = $Verdict
        DaysSaved               = $DaysSaved
        PctSaved                = $PctSaved
        HoursSaved              = $HoursSaved
        StoryPointsSaved        = $StoryPointsSaved
        Note                    = $Note
    }
}

$report = @()

$storyPointsFieldId = Get-StoryPointsFieldId
if (-not $storyPointsFieldId) {
    Write-Host "Couldn't find a 'Story Points' or 'Story point estimate' field on this JIRA site - expected-days figures will be skipped for all tickets."
}

$storyPointMapping = Get-StoryPointMapping -Path $StoryPointMappingPath

foreach ($ticketKey in $TicketList) {
    try {
        $changelog = Get-JiraChangelog -TicketKey $ticketKey
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 404) {
            $note = "JIRA 404: typo'd/nonexistent ticket, or no view permission (JIRA returns 404 for both, deliberately)"
            Write-Host "$ticketKey`: $note"
        } else {
            $note = "JIRA request failed: $($_.Exception.Message)"
            Write-Host "$ticketKey`: $note"
        }
        $report += New-ReportRow -TicketKey $ticketKey -Note $note
        continue
    }

    $transitions = Get-StatusTransitions -Changelog $changelog

    Write-Host "`n=== $ticketKey - actual prompts asked ==="
    $promptsAskedCount = 0
    try {
        $promptResult = Get-PromptTexts -TicketKey $ticketKey
        $promptsAskedCount = $promptResult.hits.Count
        if ($promptResult.hits.Count -eq 0) {
            Write-Host "(none found)"
        } else {
            $i = 1
            foreach ($p in $promptResult.hits) {
                Write-Host "$i. [$($p.repo_name)] $($p.body)"
                $i++
            }
        }
    } catch {
        Write-Host "Couldn't fetch prompt text: $($_.Exception.Message)"
    }
    Write-Host ""

    $windowStart      = ($transitions | Where-Object { $_.To -eq $InProgressStatus } | Select-Object -First 1).When
    $doneTransition   = ($transitions | Where-Object { $_.To -eq $DoneStatus }      | Select-Object -Last 1).When

    if (-not $windowStart) {
        $note = "No '$InProgressStatus' transition found - check status names against the table above"
        Write-Host $note
        $report += New-ReportRow -TicketKey $ticketKey -Note $note
        continue
    }

    $stillOpen = $false
    if ($doneTransition) {
        $windowEnd = $doneTransition
    } else {
        # Not an error - most tickets you check will still be in flight.
        # Measure from "in progress" up to right now instead of requiring
        # a terminal status to already exist.
        $windowEnd = [DateTimeOffset]::UtcNow
        $stillOpen = $true
        $currentStatus = ($transitions | Select-Object -Last 1).To
        Write-Host "No '$DoneStatus' transition yet - measuring elapsed time from '$InProgressStatus' through now ($windowEnd). Current status appears to be '$currentStatus' (last known transition), not necessarily '$InProgressStatus' - that name refers to the window's START point only."
    }

    try {
        $result = Get-UsageInWindow -TicketKey $ticketKey -Start $windowStart -End $windowEnd
    } catch {
        $note = "OpenObserve query failed: $($_.Exception.Message)"
        Write-Host $note
        $report += New-ReportRow -TicketKey $ticketKey -InProgressAt $windowStart -ClosedAt $windowEnd -Note $note
        continue
    }

    $stillOpenLabel = if ($stillOpen) { "still open" } else { "$windowEnd" }
    $lifecycleHours = [Math]::Round(($windowEnd - $windowStart).TotalHours, 2)

    $inProgressDuration = Get-CumulativeStatusDuration -Transitions $transitions -Status $InProgressStatus -Now ([DateTimeOffset]::UtcNow)
    $inProgressHours    = [Math]::Round($inProgressDuration.TotalHours, 2)

    # --- Claude usage specifically between "In Progress" and "Under Review" ---
    # This is the number that actually answers "how much did I use Claude
    # to do the work", as opposed to LifecycleHours/InProgressHours, which
    # both include calendar time you weren't necessarily touching Claude at
    # all (testing, waiting, other work). Bounded to the FIRST move into
    # $ReviewStatus after $windowStart - if the ticket bounced back out of
    # review and re-entered later, only the first pass is counted here.
    $reviewTransition = ($transitions | Where-Object { $_.To -eq $ReviewStatus -and $_.When -ge $windowStart } | Select-Object -First 1).When
    $preReviewHours = ""
    $claudeHoursBeforeReview = ""
    $costBeforeReview = ""
    $pctUsedBeforeReview = ""
    $duringReviewHours = ""
    $claudeHoursDuringReview = ""
    $costDuringReview = ""
    if ($reviewTransition) {
        $preReviewHours = [Math]::Round(($reviewTransition - $windowStart).TotalHours, 2)
        try {
            $preReviewResult = Get-UsageInWindow -TicketKey $ticketKey -Start $windowStart -End $reviewTransition
            $claudeHoursBeforeReview = [Math]::Round((Get-SafeSum -Objects $preReviewResult.hits -Property "claude_hours"), 3)
            $costBeforeReview = [Math]::Round((Get-SafeSum -Objects $preReviewResult.hits -Property "cost_usd"), 2)
            if ($preReviewHours -gt 0) {
                $pctUsedBeforeReview = [Math]::Round(($claudeHoursBeforeReview / $preReviewHours) * 100, 1)
            }
        } catch {
            Write-Host "$ticketKey`: couldn't compute pre-review usage: $($_.Exception.Message)"
        }

        # If ClaudeHoursBeforeReview comes back at or near 0, that's not
        # necessarily a bug - it can mean the real usage happened AFTER the
        # ticket moved to review (the exact GGLOBDRA-1755 pattern this
        # script already flags elsewhere). This checks that directly rather
        # than leaving it as an unverified assumption.
        try {
            $duringReviewResult = Get-UsageInWindow -TicketKey $ticketKey -Start $reviewTransition -End $windowEnd
            $claudeHoursDuringReview = [Math]::Round((Get-SafeSum -Objects $duringReviewResult.hits -Property "claude_hours"), 3)
            $costDuringReview = [Math]::Round((Get-SafeSum -Objects $duringReviewResult.hits -Property "cost_usd"), 2)
            $duringReviewHours = [Math]::Round(($windowEnd - $reviewTransition).TotalHours, 2)
        } catch {
            Write-Host "$ticketKey`: couldn't compute during-review usage: $($_.Exception.Message)"
        }
    }

    # Combined total: before-review + during-review Claude hours, against
    # the full ticket lifecycle - covers the real scenario where a
    # reviewer asks for changes and Claude is used again to make them,
    # not just the initial build.
    $totalClaudeHours = ""
    $totalUsagePct = ""
    $totalCostUsd = ""
    $beforeHours = if ($claudeHoursBeforeReview -ne "") { $claudeHoursBeforeReview } else { 0 }
    $duringHours = if ($claudeHoursDuringReview -ne "") { $claudeHoursDuringReview } else { 0 }
    if ($reviewTransition) {
        $totalClaudeHours = [Math]::Round($beforeHours + $duringHours, 3)
        $beforeCost = if ($costBeforeReview -ne "") { $costBeforeReview } else { 0 }
        $duringCost = if ($costDuringReview -ne "") { $costDuringReview } else { 0 }
        $totalCostUsd = [Math]::Round($beforeCost + $duringCost, 2)
    }
    if ($lifecycleHours -gt 0 -and $totalClaudeHours -ne "") {
        $totalUsagePct = [Math]::Round(($totalClaudeHours / $lifecycleHours) * 100, 1)
    }

    

    # --- Story points -> expected day RANGE (from story-points.yaml) -> verdict ---
    # See the .NOTES ON StoryPoints section above before trusting this.
    #
    # Deliberately NOT gated on "-not $stillOpen" anymore - a still-open
    # ticket already has a resolved "In Progress" -> "Under Review"
    # transition (if it's reached that far), which is everything
    # DaysSaved/HoursSaved/StoryPointsSaved actually need; none of that
    # requires "Closed" to exist yet. ActualDays/Verdict below DO still
    # depend on $lifecycleHours, which keeps growing for an open ticket -
    # that's fine, it just means these are a "so far" snapshot rather
    # than final, and Verdict is labeled "(still open)" so that's obvious
    # rather than silently looking like a finished result.
    $storyPoints     = $null
    $expectedMinDays = ""
    $expectedMaxDays = ""
    $actualDays      = ""
    $verdict         = ""
    if ($storyPointsFieldId) {
        try {
            $storyPoints = Get-StoryPoints -TicketKey $ticketKey -FieldId $storyPointsFieldId
            if ($storyPoints) {
                $actualDays = [Math]::Round($lifecycleHours / 24.0, 2)
                $key = Resolve-StoryPointKey -StoryPoints $storyPoints
                if ($storyPointMapping -and $storyPointMapping.ContainsKey($key)) {
                    $expectedMinDays = $storyPointMapping[$key].MinDays
                    $expectedMaxDays = $storyPointMapping[$key].MaxDays
                    if ($actualDays -lt $expectedMinDays) {
                        $verdict = "under"
                    } elseif ($actualDays -gt $expectedMaxDays) {
                        $verdict = "over"
                    } else {
                        $verdict = "within"
                    }
                    if ($stillOpen) {
                        $verdict = "$verdict (still open - so far, not final)"
                    }
                } else {
                    $verdict = "unmapped"
                }
            }
        } catch {
            Write-Host "$ticketKey`: couldn't fetch story points: $($_.Exception.Message)"
        }
    }

    # --- Time saved: actual "In Progress" -> "Under Review" duration vs. the
    # story point estimate's minimum expected days ---
    # Uses ExpectedMinDays specifically (not the midpoint or max) as a
    # deliberately conservative baseline: if you beat the FASTEST-case
    # estimate, that's a guaranteed minimum saving - the true estimate
    # could have been anywhere in the range, so this never overstates it.
    # Zero (not negative) if the range wasn't beaten - "saved" doesn't
    # apply when it took as long as, or longer than, even the minimum.
    $preReviewDays = if ($preReviewHours -ne "") { [Math]::Round($preReviewHours / 24.0, 2) } else { "" }
    $daysSaved = ""
    $pctSaved = ""
    $hoursSaved = ""
    $storyPointsSaved = ""
    if ($preReviewDays -ne "" -and $expectedMinDays -ne "") {
        if ($preReviewDays -lt $expectedMinDays) {
            $daysSaved = [Math]::Round($expectedMinDays - $preReviewDays, 2)
            $pctSaved = [Math]::Round(($daysSaved / $expectedMinDays) * 100, 1)
        } else {
            $daysSaved = 0
            $pctSaved = 0
        }

        # Hours saved: a direct unit conversion, days -> hours.
        $hoursSaved = [Math]::Round($daysSaved * $HoursPerDay, 2)

        # Story points saved: NOT just reusing $daysSaved as-is - that would
        # only be correct by coincidence if this mapping's min-days happens
        # to equal the story-point number itself (true for every entry in
        # the shipped story-points.yaml, but not guaranteed if someone
        # reconfigures it). Scaling by (StoryPoints / ExpectedMinDays)
        # converts "days saved" into the equivalent story-point unit
        # correctly either way - for the shipped config that ratio is
        # exactly 1, so the number comes out the same as DaysSaved.
        if ($storyPoints -and $expectedMinDays -gt 0) {
            $storyPointsSaved = [Math]::Round($daysSaved * ($storyPoints / $expectedMinDays), 2)
        }
    }

    if ($result.hits.Count -eq 0) {
        $note = if ($stillOpen) { "No usage found (still open, measured through now)" } else { "No usage found in window" }
        $report += New-ReportRow -TicketKey $ticketKey -PromptsAsked $promptsAskedCount -InProgressAt $windowStart -ClosedAt $stillOpenLabel -LifecycleHours $lifecycleHours -InProgressHours $inProgressHours `
            -ReviewAt $reviewTransition -PreReviewHours $preReviewHours -ClaudeHoursBeforeReview $claudeHoursBeforeReview -PctUsedBeforeReview $pctUsedBeforeReview `
            -DuringReviewHours $duringReviewHours -ClaudeHoursDuringReview $claudeHoursDuringReview -TotalClaudeHours $totalClaudeHours -TotalUsagePct $totalUsagePct -TotalCostUsd $totalCostUsd `
            -StoryPoints $storyPoints -ExpectedMinDays $expectedMinDays -ExpectedMaxDays $expectedMaxDays -ActualDays $actualDays -Verdict $verdict `
            -PreReviewDays $preReviewDays -DaysSaved $daysSaved -PctSaved $pctSaved -HoursSaved $hoursSaved -StoryPointsSaved $storyPointsSaved -Note $note
    } else {
        $note = if ($stillOpen) { "still open, measured through now" } else { "" }
        foreach ($hit in $result.hits) {
            $overlapPct           = if ($lifecycleHours -gt 0)    { [Math]::Round(($hit.claude_hours / $lifecycleHours) * 100, 1) }    else { "" }
            $inProgressOverlapPct = if ($inProgressHours -gt 0)   { [Math]::Round(($hit.claude_hours / $inProgressHours) * 100, 1) }   else { "" }
            $report += New-ReportRow -TicketKey $ticketKey -Repo $hit.repo_name -PromptsAsked $promptsAskedCount -InProgressAt $windowStart -ClosedAt $stillOpenLabel `
                -Events $hit.events -InputTokens $hit.input_tokens -OutputTokens $hit.output_tokens `
                -CacheReadTokens $hit.cache_read_tokens -CacheCreationTokens $hit.cache_creation_tokens `
                -ClaudeHours $hit.claude_hours -CostUsd $hit.cost_usd -LifecycleHours $lifecycleHours -OverlapPct $overlapPct `
                -InProgressHours $inProgressHours -InProgressOverlapPct $inProgressOverlapPct `
                -ReviewAt $reviewTransition -PreReviewHours $preReviewHours -ClaudeHoursBeforeReview $claudeHoursBeforeReview -PctUsedBeforeReview $pctUsedBeforeReview `
                -DuringReviewHours $duringReviewHours -ClaudeHoursDuringReview $claudeHoursDuringReview -TotalClaudeHours $totalClaudeHours -TotalUsagePct $totalUsagePct -TotalCostUsd $totalCostUsd `
                -StoryPoints $storyPoints -ExpectedMinDays $expectedMinDays -ExpectedMaxDays $expectedMaxDays -ActualDays $actualDays -Verdict $verdict `
                -PreReviewDays $preReviewDays -DaysSaved $daysSaved -PctSaved $pctSaved -HoursSaved $hoursSaved -StoryPointsSaved $storyPointsSaved -Note $note
        }
    }
}

Write-Host "`n=== Report ==="
$report | Format-Table -AutoSize -Property `
    Ticket, `
    Repo, `
    @{Label = "PromptsAsked"; Expression = { $_.PromptsAsked } }, `
    @{Label = "Total Tokens"; Expression = { $_.InputTokens + $_.OutputTokens + $_.CacheReadTokens + $_.CacheCreationTokens } }, `
    @{Label = "Total Hrs Actual Work"; Expression = { $_.TotalClaudeHours } }, `
    @{Label = "Total Cost USD"; Expression = { $_.TotalCostUsd } }, `
    @{Label = "Hrs Saved"; Expression = { $_.HoursSaved } }, `
    @{Label = "Story Point Saved"; Expression = { $_.StoryPointsSaved } } `
    | Out-String -Width 300 | Write-Host

# Everything below is commented out, not removed - all of these fields
# are still computed and written to the CSV regardless of what's shown
# on screen. Uncomment (and move) any of these back into the -Property
# list above if you want them visible in the console again:
#     StoryPoints, `
#     ActualDays, `
#     @{Label = "InProgressToReviewDays"; Expression = { $_.PreReviewDays } }, `
#     @{Label = "input_tokens"; Expression = { $_.InputTokens } }, `
#     ClaudeHoursDuringReview, `
#     @{Label = "TotalClaudeHours"; Expression = { $_.TotalClaudeHours } }, `
#     @{Label = "Claude Usage %"; Expression = { $_.TotalUsagePct } }, `
#     @{Label = "Days Saved"; Expression = { $_.DaysSaved } }, `
#     @{Label = "Saved %"; Expression = { $_.PctSaved } }, `

try {
    $report | Export-Csv -Path $OutputCsv -NoTypeInformation
    Write-Host "`nFull details (all columns) written to $OutputCsv"
} catch {
    Write-Host "`nCouldn't write to '$OutputCsv': $($_.Exception.Message)"
    Write-Host "This usually means the file is already open in Excel or another program - close it and re-run, or pass a different -OutputCsv path. The report above was still computed correctly; only the CSV write failed."
}