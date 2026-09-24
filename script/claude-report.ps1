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
    Defaults to "In Progress" / "Closed","Development Done" (DoneStatus
    accepts several names; any of them counts as finished) - check the printed transition
    table if these don't match your workflow and re-run with the right
    values.

.PARAMETER StoryPointMappingPath
    Path to a YAML file mapping story points to an expected duration
    range in days - see story-points.yaml alongside this script for the
    format. Defaults to story-points.yaml in this script's own folder
    (not the current directory). If the file is missing, or
    a ticket's story point value has no entry in it, the expected-days
    comparison is simply skipped for that ticket (not an error).

.PARAMETER HoursPerDay
    Working hours per day, used only to convert DaysSaved into
    HoursSaved. Defaults to 8.

.PARAMETER OutputCsv
    Where to write the combined report. Defaults to
    claude-report.csv in the current directory. Written even for a
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
    2. "Actual days" = business days elapsed (Mon-Fri only, Saturday and
       Sunday excluded entirely) from first "In Progress" to Closed -
       see .NOTES ON Business-day calculation below for exactly how this
       works and why it changed from a plain hours/24 calculation.
    3. Attributing a ticket landing "under" its range specifically to
       Claude is an assumption, not a measurement - there's no
       counterfactual (the same ticket completed without Claude) to
       compare against. Best read as "actual vs. your team's own
       estimate range, during a period when Claude was used" rather
       than proven causation.

.NOTES ON Business-day calculation (Get-BusinessDaysElapsed, Get-ActiveBusinessDaysElapsed)
    PreReviewDays and ActualDays used to be a plain (hours / 24)
    calculation - which counts Saturday and Sunday as full ordinary
    workdays, same as any weekday. Confirmed wrong on a real ticket:
    someone started work Friday, was on leave over the weekend, came
    back Monday and finished Tuesday - the plain-hours calculation
    counted that weekend as ~2 extra days of "time to complete",
    inflating CompletionHours/DaysSaved/HoursSaved/Verdict by 16
    work-hours that were never actually available to work in the first
    place.

    Get-BusinessDaysElapsed walks day by day between the two
    timestamps, counting only Monday-Friday - Saturday/Sunday contribute
    zero, regardless of how much of that calendar day falls inside the
    window. Partial first/last days are handled proportionally (e.g. a
    ticket that moved to "In Progress" on a Friday at 3pm only counts
    the fraction of that Friday from 3pm to midnight, not the whole
    day) - so this isn't just "count whole calendar dates", it produces
    the same kind of fractional-day precision the old calculation did,
    just with weekends correctly excluded.

    This does NOT account for public holidays, or any other kind of
    planned leave that doesn't have its own distinct JIRA status - if
    your team wants that level of accuracy, the workflow would need a
    status like "Blocked"/"On Hold" that gets set during known leave,
    which this script could then be extended to subtract explicitly.
    Without that signal, there's no way to distinguish "genuinely
    working slowly" from "on leave" from raw JIRA timestamps alone.

    ActualDays/PreReviewDays don't call Get-BusinessDaysElapsed directly
    any more - they go through Get-ActiveBusinessDaysElapsed, which sums
    only the stretches actually spent in an active status ($InProgressStatus
    / $ReviewStatus), running Get-BusinessDaysElapsed over each qualifying
    stretch. A ticket can bounce back to a non-active status (e.g. "Open")
    mid-lifecycle and re-enter "In Progress" later (confirmed for real on
    GGLOBDRA-2013: parked in "Open" for ~12 days between two "In Progress"
    stretches) - a plain first-transition-to-last-transition span, even
    with weekends excluded, still counts that parked time as "time to
    complete". See Get-ActiveBusinessDaysElapsed's own comment for the
    full story; Get-CumulativeStatusDuration already handled the same
    bounce-back shape for InProgressHours (see GGLOBDRA-1755 there) but
    didn't feed ActualDays/CompletionHours/HoursSaved until now.

.NOTES ON assignee-based completion window (Get-CurrentAssigneeSince)
    Even with Get-ActiveBusinessDaysElapsed excluding non-active stretches
    (above), GGLOBDRA-2013 still overstated CompletionHours: its early
    active-status time (a 5-minute "In Progress" blip, then 9 days sitting
    in "Under Review") happened while the ticket was UNASSIGNED - nobody
    was actually working it. It was reassigned to its real owner on
    2026-09-09, who closed it the next day; that ~1-business-day stretch
    was the genuine work, not the ~8 business days of active-status time
    the ticket's whole history summed to.

    $completionWindowStart (computed once per ticket, right after
    $windowEnd) clips the start of the completion-time calculation forward
    to when the ticket's FINAL assignee (as of $windowEnd) took ownership,
    via Get-CurrentAssigneeSince - but only if that's later than
    $windowStart; a ticket assigned before it ever started, or never
    reassigned, is unaffected. This feeds ActualDays, PreReviewDays,
    ReviewTransition (and therefore PreReviewHours/ClaudeHoursBeforeReview/
    ClaudeHoursDuringReview), CompletionHours, HoursSaved, and
    StoryPointsSaved.

    Deliberately does NOT touch $windowStart itself, InProgressAt,
    LifecycleHours, or InProgressHours - those stay anchored to the
    ticket's true first "In Progress" transition, so the full raw history
    is still visible in the CSV even when the Saved-metrics calculation
    ignores part of it. SavedBasis is suffixed with the clip explanation
    whenever it actually changes the completion window used, so this is
    never silently invisible in the output.

    Only clips at assignee-CHANGE boundaries pulled from the changelog -
    it has no way to tell "actively working" from "assigned but blocked
    on something else" within a single assignee's tenure. Same class of
    blind spot as the business-day/public-holiday one above.

.NOTES ON TotalClaudeHours / TotalUsagePct / TotalCostUsd
    TotalClaudeHours = ClaudeHoursBeforeReview + ClaudeHoursDuringReview +
    ClaudeHoursPostClosure - real Claude session time across all three
    phases: before the ticket moved to review, during review, and after
    it was marked Closed. The post-closure phase covers real activity
    that happens after closure (e.g. a final test-suite re-run or rebase
    verification) - genuine, ticket-relevant work that a window ending
    at "Closed" would otherwise silently miss. TotalUsagePct is the
    combined total against the full ticket lifecycle. TotalCostUsd is
    the same three-way sum, in USD. All of these are blank (not zero) if
    no "Under Review" transition was found - there's nothing to sum in
    that case, which is different from a genuine zero.

    ClaudeHoursPostClosure/CostPostClosure/PostClosureHours are also
    shown on their own (not just folded into the totals), specifically
    so it's visible how much of a ticket's total came from after it was
    already marked done - worth a second look on any ticket where this
    is unexpectedly large. Post-closure is open-ended (Closed -> now),
    not bounded by another status transition, since there's nothing
    further to bound it by.

.NOTES ON TotalTokensAllPhases
    A single ticket-wide total (main In-Progress-to-Closed window,
    summed across every repo it touched, PLUS pre-review + during-review
    + post-closure) - shown IDENTICALLY on every repo row, exactly like
    TotalClaudeHours/TotalCostUsd already do. Deliberately NOT a
    per-repo figure (an earlier version added the full ticket-wide
    review-phase total onto each repo's own slice separately, which
    silently multiplied that portion once per repo if anyone summed the
    column across a ticket's rows) - summing this column across a
    ticket's repo rows will overcount; read it once per ticket, not once
    per repo.

    Console shows this broken down by type too (Input/Output/
    CacheRead/CacheCreate, all M/B-formatted via Format-BigNumber for
    readability - the CSV always keeps the full unrounded number
    regardless). CacheRead usually dominates the total by a wide margin
    on any session that's run long - every turn in an agentic session
    re-sees the entire accumulated context, and a cache hit means that
    got re-read cheaply rather than reprocessed from scratch. This is
    exactly why a Total Tokens figure in the tens/hundreds of millions
    can still cost relatively little: CacheRead is billed at 0.1x normal
    input rate. TotalCostUsd already accounts for all four types at
    their correct differing rates (input, output, CacheRead at 0.1x,
    CacheCreate at 1.25x - the latter costs slightly more than a normal
    input token, since it's doing extra work to store it for reuse) - a
    bare Total Tokens number alone will look alarming relative to actual
    cost if CacheRead dominates it, which is normal, not a bug.

.NOTES ON DaysSaved / PctSaved
    IMPORTANT: this does NOT factor in Claude usage hours at all - it's
    purely elapsed BUSINESS-DAY time ("In Progress" to "Under Review",
    weekends excluded - see .NOTES ON Business-day calculation)
    compared against the story-point estimate. It has no connection to
    TotalClaudeHours/TotalUsagePct/ClaudeHoursDuringReview - a ticket
    could show a large Saved% while barely using Claude, or a small one
    despite heavy use. Treat them as two separate questions ("did it
    finish faster than estimated" vs. "how much was Claude actually
    used"), not one combined metric.

    DaysSaved = ExpectedMinDays - CompletionDays, where CompletionDays is
    the "In Progress" to "Under Review" duration if that transition
    exists, or the full lifecycle (In Progress to Closed) if the
    workflow has no distinct "Under Review" step at all - SavedBasis
    records which one was actually used, so this is never ambiguous.
    Deliberately uses ExpectedMinDays specifically, not the midpoint or
    max of the range: if you beat the FASTEST-case estimate, that's a
    guaranteed minimum saving regardless of where the true estimate
    actually sat in the range - this never overstates a genuine saving.
    PctSaved = DaysSaved / ExpectedMinDays * 100.

    CAN BE NEGATIVE - deliberately not clamped to 0. A negative value
    (e.g. -6.14) means the ticket took that many days LONGER than even
    the fastest-case estimate, which is real, useful information -
    clamping it to 0 would hide exactly how far over a bad estimate a
    ticket actually went.

    Same causation caveat as everything else here: this shows the gap
    between actual time and your team's own estimate, during a period
    Claude was used - not proof Claude caused the difference.

    HoursSaved = DaysSaved * HoursPerDay (default 8) - a plain unit
    conversion, nothing more. Same sign as DaysSaved - can be negative.
    The one-line ticket summary's "finished in X hrs" (CompletionHours)
    uses this SAME HoursPerDay basis, deliberately - not real calendar
    hours (24/day) - so the two figures in that sentence stay directly
    comparable rather than silently mismatched units.

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
    $env:OPENOBSERVE_URL = "http://localhost:5080"   # or wherever it's reachable on YOUR machine
    $env:OPENOBSERVE_USER = "root@example.com"
    $env:OPENOBSERVE_PASSWORD = "your-real-password"

    # Then every run is just this:
    .\claude-report.ps1 -Ticket GGLOBDRA-1813

.EXAMPLE
    # -Ticket is positional - the flag name can be dropped
    .\claude-report.ps1 GGLOBDRA-1813

.EXAMPLE
    # A batch, from a file, into a named report (still just needs -Tickets/-TicketsFile
    # once the environment variables above are set)
    .\claude-report.ps1 -TicketsFile .\tickets.txt -OutputCsv .\q3-report.csv

.EXAMPLE
    # Overriding a value just for one run still works normally
    .\claude-report.ps1 -Ticket GGLOBDRA-1813 -OpenObserveUrl "http://otherhost:5080"

.NOTES
    Credentials are parameters/environment variables, never hardcoded -
    safe to keep this file in source control as-is.
#>

param(
    [Parameter(Position = 0)]
    [string]$Ticket,
    [string[]]$Tickets,
    [string]$TicketsFile,

    [string]$InProgressStatus = "In Progress",
    [string[]]$DoneStatus = @("Closed", "Development Done"),
    [string]$ReviewStatus = "Under Review",

    [string]$JiraBase = $env:JIRA_BASE,
    [string]$JiraUser = $env:JIRA_USER,
    [string]$JiraToken = $env:JIRA_TOKEN,

    # Not hardcoded to a specific host/IP, and not just "http://localhost:5080"
    # either - which OpenObserve is actually reachable at depends on how
    # THIS machine runs the container (Docker Desktop, Podman Desktop,
    # Podman machine on WSL, etc), and that varies per person/machine, not
    # per checkout of this script. Podman in particular has been seen NOT
    # forwarding the published port to Windows "localhost" the way Docker
    # Desktop does, landing instead on the Podman machine's own VM IP
    # (`podman machine inspect` shows it, under ConnectionInfo). Falls back
    # to localhost:5080 (the common case) only if $env:OPENOBSERVE_URL isn't
    # set - set it once via setEnvironment.ps1 (writes it to $PROFILE,
    # alongside JIRA_BASE/OPENOBSERVE_USER/OPENOBSERVE_PASSWORD, the same
    # per-machine values it already manages) rather than editing this
    # script's default, which would only fix it for you, not for anyone
    # else who pulls this file.
    [string]$OpenObserveUrl = $(if ($env:OPENOBSERVE_URL) { $env:OPENOBSERVE_URL } else { "http://localhost:5080" }),
    [string]$OpenObserveOrg = "default",
    [string]$OpenObserveUser = $env:OPENOBSERVE_USER,
    [string]$OpenObservePassword = $env:OPENOBSERVE_PASSWORD,

    [string]$StoryPointMappingPath = (Join-Path $PSScriptRoot "story-points.yaml"),
    [double]$HoursPerDay = 8,

    [string]$OutputCsv = ".\claude-report.csv",

    # Opt-in only - pushes each ticket's already-computed summary (HoursSaved,
    # StoryPointsSaved, etc.) into a new OpenObserve stream, so those
    # JIRA-dependent figures become dashboard-able. Off by default - this
    # writes data, unlike everything else in this script, which only reads.
    [switch]$PushToOpenObserve,
    [string]$SummaryStream = "claude_report_summary"
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

# Fail fast on bad JIRA credentials. A rejected email/token pair doesn't
# error on its own - JIRA silently falls back to anonymous access, which
# surfaces later as a misleading "Story Points field not found" plus a 404
# on every ticket (anonymous users can't see them). /myself is the one
# endpoint that returns a clean 401 in that case, so check it up front.
try {
    $jiraMe = Invoke-RestMethod -Uri "$JiraBase/rest/api/3/myself" -Headers $jiraHeaders -Method Get
    Write-Host "JIRA auth OK as $($jiraMe.emailAddress)`n"
} catch {
    $authStatus = $_.Exception.Response.StatusCode.value__
    if ($authStatus -eq 401 -or $authStatus -eq 403) {
        Write-Host "JIRA auth failed ($authStatus) for '$JiraUser' at $JiraBase - the email/token pair was rejected."
        Write-Host "  - Check the token was created while logged in as '$JiraUser': https://id.atlassian.com/manage-profile/security/api-tokens"
        Write-Host "  - Check it hasn't expired or been revoked, and is a classic token (not 'with scopes')"
        Write-Host "  - After fixing, re-run setEnvironment.ps1 and open a NEW terminal so `$PROFILE reloads"
    } else {
        Write-Host "Couldn't reach JIRA at $JiraBase to verify credentials: $($_.Exception.Message)"
    }
    return
}

$ooPair    = "$OpenObserveUser`:$OpenObservePassword"
$ooBase64  = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($ooPair))
$ooHeaders = @{ Authorization = "Basic $ooBase64"; "Content-Type" = "application/json" }

function Format-BigNumber {
    # Formats a plain number as K/M/B for readability in the console
    # table only - the CSV always keeps the raw, unrounded number, so
    # nothing precise is ever lost to this formatting.
    param([double]$Value)
    if ($Value -ge 1000000000) {
        return "$([Math]::Round($Value / 1000000000, 2))B"
    } elseif ($Value -ge 1000000) {
        return "$([Math]::Round($Value / 1000000, 2))M"
    } elseif ($Value -ge 1000) {
        return "$([Math]::Round($Value / 1000, 1))K"
    } else {
        return "$Value"
    }
}

function Send-TicketSummaryToOpenObserve {
    # Pushes the already-computed, JIRA-dependent figures (HoursSaved,
    # StoryPointsSaved, etc.) into OpenObserve as their own stream -
    # claude_code_history has no JIRA data in it at all, so those figures
    # can never be produced by a query against it alone. This is the only
    # way to make them dashboard-able: compute them here (where JIRA data
    # is actually available), then store the result as data OpenObserve
    # can query like anything else.
    #
    # Uses OpenObserve's plain JSON ingest endpoint (_json), not the OTLP
    # log format claude-history-ingestor uses - simpler, and appropriate
    # here since this is a small, custom, application-level dataset, not
    # a stream of session events.
    param($Summary)

    $uri = "$OpenObserveUrl/api/$OpenObserveOrg/$SummaryStream/_json"
    $body = @(, $Summary) | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $uri -Headers $ooHeaders -Method Post -Body $body | Out-Null
    } catch {
        Write-Host "$($Summary.ticket): couldn't push summary to OpenObserve: $($_.Exception.Message)"
    }
}

function Get-BusinessDaysElapsed {
    # Walks day by day from Start to End, counting only Monday-Friday -
    # Saturday/Sunday contribute zero, regardless of how much of that
    # calendar day falls within the window. Partial first/last days are
    # handled proportionally, so a ticket that moved to "In Progress" on
    # a Friday at 3pm only counts the fraction of that Friday from 3pm
    # to midnight, not the whole day.
    #
    # Replaces a plain (hours / 24) calculation that counted weekends in
    # full, as if they were ordinary workdays - confirmed wrong on a
    # real ticket where someone worked Friday, was on leave over the
    # weekend, and returned Monday: the old calculation counted that
    # weekend as ~2 extra days of "time to complete". See .NOTES ON
    # Business-day calculation above for the full explanation, including
    # what this still doesn't account for (public holidays, other leave
    # without a distinct JIRA status).
    param([DateTimeOffset]$Start, [DateTimeOffset]$End)

    if ($End -le $Start) { return 0.0 }

    $totalDays = 0.0
    $current = $Start
    while ($current -lt $End) {
        # Deliberately NOT $current.Date - that property returns a plain
        # DateTime, not a DateTimeOffset, which silently broke every
        # comparison below it (a real bug caught by an actual run, not
        # just theory: PowerShell threw "Cannot convert DateTimeOffset to
        # DateTime" on the -lt comparison, then a null-reference error on
        # the next loop iteration once the mismatch had already corrupted
        # $segmentEnd). Constructing the DateTimeOffset explicitly, using
        # $current's own offset, keeps everything in DateTimeOffset the
        # whole way through - no implicit type change anywhere.
        $midnightToday = [DateTimeOffset]::new($current.Year, $current.Month, $current.Day, 0, 0, 0, $current.Offset)
        $nextMidnight = $midnightToday.AddDays(1)
        $segmentEnd = if ($nextMidnight -lt $End) { $nextMidnight } else { $End }
        $fractionOfDay = ($segmentEnd - $current).TotalHours / 24.0
        if ($current.DayOfWeek -ne [System.DayOfWeek]::Saturday -and $current.DayOfWeek -ne [System.DayOfWeek]::Sunday) {
            $totalDays += $fractionOfDay
        }
        $current = $segmentEnd
    }
    return $totalDays
}

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

function Get-ActiveBusinessDaysElapsed {
    # Get-BusinessDaysElapsed alone still overcounts a ticket that bounces
    # OUT of active work and back to a non-active status (e.g. "Open") mid-
    # lifecycle, then re-enters "In Progress" later - confirmed on a real
    # ticket, GGLOBDRA-2013: In Progress -> Under Review -> In Progress ->
    # Open (parked for ~12 days) -> In Progress -> Under Review -> Closed.
    # windowStart-to-windowEnd spans that whole parked stretch, so plain
    # business-day elapsed counted it as "time to complete" and drove
    # CompletionHours to 129 against a 16-32hr estimate, tanking
    # HoursSaved/StoryPointsSaved deeply negative even though the ticket
    # wasn't actually being worked on for most of that gap.
    #
    # Get-CumulativeStatusDuration already exists to handle this exact
    # bounce-back shape (its own comment cites GGLOBDRA-1755), but only
    # feeds InProgressHours, not ActualDays/PreReviewDays/CompletionHours/
    # HoursSaved. This applies the same "sum every stretch, not just
    # first-to-last" fix to those, layered on top of the existing
    # weekend-exclusion (Get-BusinessDaysElapsed) rather than replacing it:
    # only time spent in an $ActiveStatuses status, on a weekday, counts.
    #
    # Walks every transition, and for each stretch that entered an active
    # status, clips it to [$Start, $End] and runs Get-BusinessDaysElapsed
    # over just that clipped stretch - a non-active stretch (e.g. "Open")
    # contributes nothing, regardless of how many weekdays it spans.
    param([array]$Transitions, [DateTimeOffset]$Start, [DateTimeOffset]$End, [string[]]$ActiveStatuses, [DateTimeOffset]$Now)

    if ($End -le $Start) { return 0.0 }

    $total = 0.0
    for ($i = 0; $i -lt $Transitions.Count; $i++) {
        if ($ActiveStatuses -contains $Transitions[$i].To) {
            $stretchStart = $Transitions[$i].When
            $stretchEnd = if ($i + 1 -lt $Transitions.Count) { $Transitions[$i + 1].When } else { $Now }
            $clipStart = if ($stretchStart -gt $Start) { $stretchStart } else { $Start }
            $clipEnd = if ($stretchEnd -lt $End) { $stretchEnd } else { $End }
            if ($clipEnd -gt $clipStart) {
                $total += (Get-BusinessDaysElapsed -Start $clipStart -End $clipEnd)
            }
        }
    }
    return $total
}

function Get-CurrentAssigneeSince {
    # Returns when the ticket's final assignee (as of $Before) actually
    # took ownership - the most recent "assignee" change at/before $Before
    # whose target isn't blank. $null if the ticket was never (re)assigned,
    # or is unassigned right at $Before (nothing to clip against).
    #
    # Exists because active-status time (Get-ActiveBusinessDaysElapsed)
    # still credits earlier active-status stretches to whoever eventually
    # closes the ticket, even if those stretches happened while it was
    # unassigned or assigned to someone else entirely - confirmed on a real
    # ticket, GGLOBDRA-2013: unassigned for ~3 weeks (a stray 5-minute "In
    # Progress" blip, then 9 days sitting in "Under Review" with nobody
    # assigned, then parked back in "Open"), reassigned to its actual
    # owner on 2026-09-09, who closed it the next day. Real work was ~1
    # business day, not the ~8 business days of active-status time the
    # ticket accumulated across its whole, mostly-unassigned history.
    param([array]$Transitions, [DateTimeOffset]$Before)
    $relevant = $Transitions | Where-Object { $_.When -le $Before }
    if (-not $relevant -or ($relevant | Measure-Object).Count -eq 0) { return $null }
    $last = $relevant | Select-Object -Last 1
    if (-not $last.To) { return $null }
    return $last.When
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

function Get-AssigneeTransitions {
    # Same shape as Get-StatusTransitions, filtered to "assignee" field
    # changes instead of "status" - feeds Get-CurrentAssigneeSince (see its
    # comment, and .NOTES ON assignee-based completion window, for why this
    # exists).
    param($Changelog)
    $transitions = @()
    foreach ($history in $Changelog.values) {
        foreach ($item in $history.items) {
            if ($item.field -eq "assignee") {
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
    #
    # jira_ticket is extracted PER ROW, in the innermost subquery, and
    # filtered to $TicketKey BEFORE grouping by session - not via
    # min(code_git_branch) per session (an earlier version did this,
    # which silently missed real matching data: if the same session ever
    # touched a different ticket's branch anywhere within a wide window,
    # min() could pick that other branch as the session's "representative"
    # one instead, excluding the whole session even though real matching
    # rows existed in it). This risk grows with window width, which is
    # why it surfaced on the wide, open-ended post-closure window and not
    # the narrow pre/during-review ones.
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
    session_id, repo_name, jira_ticket,
    count(*) AS events,
    sum(llm_usage_input_tokens) AS input_tokens,
    sum(llm_usage_output_tokens) AS output_tokens,
    sum(llm_usage_cache_read_input_tokens) AS cache_read_tokens,
    sum(llm_usage_cache_creation_input_tokens) AS cache_creation_tokens,
    (max(_timestamp) - min(_timestamp)) / 1000000.0 AS duration_seconds,
    sum(CAST(llm_cost_usd AS DOUBLE)) AS cost_usd
  FROM (
    SELECT *,
      CASE WHEN re_match(code_git_branch, '[A-Z][A-Z0-9]+-[0-9]+')
        THEN regexp_replace(code_git_branch, '.*?([A-Z][A-Z0-9]+-[0-9]+).*', '`$1')
        ELSE NULL END AS jira_ticket
    FROM claude_code_history
    WHERE code_git_branch IS NOT NULL
  )
  WHERE jira_ticket = '$TicketKey'
  GROUP BY session_id, repo_name, jira_ticket
)
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
          $DuringReviewHours = "", $ClaudeHoursDuringReview = "", $CostBeforeReview = "", $CostDuringReview = "", $PostClosureHours = "", $ClaudeHoursPostClosure = "", $CostPostClosure = "", $TotalClaudeHours = "", $TotalUsagePct = "", $TotalCostUsd = "", $TotalTokensAllPhases = 0,
          $TotalInputTokens = 0, $TotalOutputTokens = 0, $TotalCacheReadTokens = 0, $TotalCacheCreationTokens = 0,
          $StoryPoints = "", $ExpectedMinDays = "", $ExpectedMaxDays = "", $ActualDays = "", $Verdict = "",
          $PreReviewDays = "", $DaysSaved = "", $PctSaved = "", $HoursSaved = "", $StoryPointsSaved = "", $SavedBasis = "", $CompletionHours = "", $Note = "")
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
        CostBeforeReview        = $CostBeforeReview
        CostDuringReview        = $CostDuringReview
        PostClosureHours        = $PostClosureHours
        ClaudeHoursPostClosure  = $ClaudeHoursPostClosure
        CostPostClosure         = $CostPostClosure
        TotalTokensAllPhases    = $TotalTokensAllPhases
        TotalInputTokens        = $TotalInputTokens
        TotalOutputTokens       = $TotalOutputTokens
        TotalCacheReadTokens    = $TotalCacheReadTokens
        TotalCacheCreationTokens = $TotalCacheCreationTokens
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
        SavedBasis              = $SavedBasis
        CompletionHours         = $CompletionHours
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
    $assigneeTransitions = Get-AssigneeTransitions -Changelog $changelog

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
    $doneTransition   = ($transitions | Where-Object { $DoneStatus -contains $_.To } | Select-Object -Last 1).When

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
        Write-Host "No '$($DoneStatus -join "' / '")' transition yet - measuring elapsed time from '$InProgressStatus' through now ($windowEnd). Current status appears to be '$currentStatus' (last known transition), not necessarily '$InProgressStatus' - that name refers to the window's START point only."
    }

    # See .NOTES ON assignee-based completion window / Get-CurrentAssigneeSince.
    # $windowStart (the ticket's very FIRST "In Progress") stays as-is for
    # InProgressAt/LifecycleHours/InProgressHours - those are meant to show
    # the ticket's full raw history. $completionWindowStart is the one
    # actually used below to compute ActualDays/PreReviewDays/CompletionHours/
    # HoursSaved/StoryPointsSaved: clipped forward to when the ticket's
    # final assignee took ownership, if that happened after $windowStart.
    $ownerSince = Get-CurrentAssigneeSince -Transitions $assigneeTransitions -Before $windowEnd
    $completionWindowStart = if ($ownerSince -and $ownerSince -gt $windowStart) { $ownerSince } else { $windowStart }

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
    $reviewTransition = ($transitions | Where-Object { $_.To -eq $ReviewStatus -and $_.When -ge $completionWindowStart } | Select-Object -First 1).When
    $preReviewHours = ""
    $claudeHoursBeforeReview = ""
    $costBeforeReview = ""
    $pctUsedBeforeReview = ""
    $tokensBeforeReview = 0
    $duringReviewHours = ""
    $claudeHoursDuringReview = ""
    $costDuringReview = ""
    $tokensDuringReview = 0
    # Explicit success flags - set to $true only at the exact moment each
    # value is genuinely computed, never inferred afterward from the
    # variable's type or contents. An earlier version tried inferring
    # "was this computed" from the value itself (first via -ne "", then
    # via -is [double]) and both were real, hard-to-verify sources of
    # doubt - this sidesteps that category of bug entirely by tracking
    # success explicitly, the same way $stillOpen/$reviewTransition
    # already track other yes/no facts directly rather than inferring them.
    $beforeReviewComputed = $false
    $duringReviewComputed = $false
    # Explicitly reset - these are only assigned inside conditional blocks
    # below, and PowerShell's if/foreach don't create new variable scopes,
    # so without this a previous ticket's stale result (in a multi-ticket
    # batch) could otherwise leak into a later ticket that has no review
    # transition of its own.
    $preReviewResult = $null
    $duringReviewResult = $null
    $postClosureResult = $null
    if ($reviewTransition) {
        $preReviewHours = [Math]::Round(($reviewTransition - $completionWindowStart).TotalHours, 2)
        try {
            $preReviewResult = Get-UsageInWindow -TicketKey $ticketKey -Start $completionWindowStart -End $reviewTransition
            $claudeHoursBeforeReview = [Math]::Round((Get-SafeSum -Objects $preReviewResult.hits -Property "claude_hours"), 3)
            $costBeforeReview = [Math]::Round((Get-SafeSum -Objects $preReviewResult.hits -Property "cost_usd"), 2)
            $tokensBeforeReview = (Get-SafeSum -Objects $preReviewResult.hits -Property "input_tokens") `
                + (Get-SafeSum -Objects $preReviewResult.hits -Property "output_tokens") `
                + (Get-SafeSum -Objects $preReviewResult.hits -Property "cache_read_tokens") `
                + (Get-SafeSum -Objects $preReviewResult.hits -Property "cache_creation_tokens")
            if ($preReviewHours -gt 0) {
                $pctUsedBeforeReview = [Math]::Round(($claudeHoursBeforeReview / $preReviewHours) * 100, 1)
            }
            $beforeReviewComputed = $true
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
            $tokensDuringReview = (Get-SafeSum -Objects $duringReviewResult.hits -Property "input_tokens") `
                + (Get-SafeSum -Objects $duringReviewResult.hits -Property "output_tokens") `
                + (Get-SafeSum -Objects $duringReviewResult.hits -Property "cache_read_tokens") `
                + (Get-SafeSum -Objects $duringReviewResult.hits -Property "cache_creation_tokens")
            $duringReviewHours = [Math]::Round(($windowEnd - $reviewTransition).TotalHours, 2)
            $duringReviewComputed = $true
        } catch {
            Write-Host "$ticketKey`: couldn't compute during-review usage: $($_.Exception.Message)"
        }
    }

    # --- Post-closure: real activity after "Closed", which the main
    # window (In Progress -> Closed) never covers on its own. Real
    # example this was built for: a full test-suite re-run and rebase
    # verification happening ~20 hours after a ticket was already marked
    # Closed - genuine work, tied to the ticket, that would otherwise be
    # silently invisible. Open-ended (Closed -> now), not bounded to
    # another status, since there's nothing further to bound it by.
    $postClosureHours = ""
    $claudeHoursPostClosure = ""
    $costPostClosure = ""
    $tokensPostClosure = 0
    if ($doneTransition) {
        $now = [DateTimeOffset]::UtcNow
        $postClosureHours = [Math]::Round(($now - $doneTransition).TotalHours, 2)
        try {
            $postClosureResult = Get-UsageInWindow -TicketKey $ticketKey -Start $doneTransition -End $now
            $claudeHoursPostClosure = [Math]::Round((Get-SafeSum -Objects $postClosureResult.hits -Property "claude_hours"), 3)
            $costPostClosure = [Math]::Round((Get-SafeSum -Objects $postClosureResult.hits -Property "cost_usd"), 2)
            $tokensPostClosure = (Get-SafeSum -Objects $postClosureResult.hits -Property "input_tokens") `
                + (Get-SafeSum -Objects $postClosureResult.hits -Property "output_tokens") `
                + (Get-SafeSum -Objects $postClosureResult.hits -Property "cache_read_tokens") `
                + (Get-SafeSum -Objects $postClosureResult.hits -Property "cache_creation_tokens")
        } catch {
            Write-Host "$ticketKey`: couldn't compute post-closure usage: $($_.Exception.Message)"
        }
    }

    # Combined total: before-review + during-review + post-closure Claude
    # hours, against the full ticket lifecycle - covers both the
    # reviewer-asks-for-changes scenario and genuine post-closure
    # verification work, not just the initial build.
    $totalClaudeHours = ""
    $totalUsagePct = ""
    $totalCostUsd = ""
    $beforeHours = if ($claudeHoursBeforeReview -ne "") { $claudeHoursBeforeReview } else { 0 }
    $duringHours = if ($claudeHoursDuringReview -ne "") { $claudeHoursDuringReview } else { 0 }
    $postClosureHoursForTotal = if ($claudeHoursPostClosure -ne "") { $claudeHoursPostClosure } else { 0 }
    if ($reviewTransition -or $doneTransition) {
        $totalClaudeHours = [Math]::Round($beforeHours + $duringHours + $postClosureHoursForTotal, 3)
        $beforeCost = if ($costBeforeReview -ne "") { $costBeforeReview } else { 0 }
        $duringCost = if ($costDuringReview -ne "") { $costDuringReview } else { 0 }
        $postClosureCostForTotal = if ($costPostClosure -ne "") { $costPostClosure } else { 0 }
        $totalCostUsd = [Math]::Round($beforeCost + $duringCost + $postClosureCostForTotal, 2)
    }
    if ($lifecycleHours -gt 0 -and $totalClaudeHours -ne "") {
        $totalUsagePct = [Math]::Round(($totalClaudeHours / $lifecycleHours) * 100, 1)
    }

    # Ticket-level token total, across all phases - NOT the same as
    # summing InputTokens/OutputTokens/CacheReadTokens/CacheCreationTokens
    # on individual repo rows below (those come only from the main
    # In-Progress-to-Closed window). A ticket whose real activity happened
    # entirely pre-review, during-review, or post-closure would otherwise
    # show 0 total tokens despite having real recorded usage.
    $tokensReviewPhases = $tokensBeforeReview + $tokensDuringReview + $tokensPostClosure

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
                # Business days elapsed (weekends excluded) from
                # "In Progress" through the end of the window, counting
                # only stretches actually spent in an active status (In
                # Progress / Under Review) - see .NOTES ON Business-day
                # calculation above and Get-ActiveBusinessDaysElapsed's own
                # comment for why a plain first-to-last span still
                # overcounts a ticket that bounces back to "Open" mid-
                # lifecycle. Previously $lifecycleHours / 24.0 (counted
                # weekends in full), then Get-BusinessDaysElapsed alone
                # (still counted parked/non-active stretches in full).
                $actualDays = [Math]::Round((Get-ActiveBusinessDaysElapsed -Transitions $transitions -Start $completionWindowStart -End $windowEnd -ActiveStatuses @($InProgressStatus, $ReviewStatus) -Now ([DateTimeOffset]::UtcNow)), 2)
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

    # --- Time saved: actual completion duration vs. the story point
    # estimate's minimum expected days ---
    # Prefers "In Progress" -> "Under Review" duration (PreReviewDays) when
    # that transition exists AND it plausibly represents real completion
    # time. Falls back to the full lifecycle (ActualDays, In Progress to
    # Closed) in TWO cases: (1) a workflow has no distinct "Under Review"
    # step at all (some projects go straight to Closed), or (2) the review
    # transition happened before any real work did - confirmed real
    # example: a ticket moved to "Under Review" in 18 minutes
    # (PreReviewHours) with ClaudeHoursBeforeReview = 0, while
    # ClaudeHoursDuringReview showed 13.4 hours of genuine work - meaning
    # "time to review" here measured an administrative status flip, not
    # completion of anything. Which basis was actually used is tracked in
    # $savedBasis so this is never ambiguous in the CSV - and case (2) is
    # labeled distinctly from case (1) so it's clear which situation
    # applied.
    #
    # The threshold (ClaudeHoursBeforeReview < 0.1 AND
    # ClaudeHoursDuringReview > 1) is deliberately narrow - it's meant to
    # catch the "review happened before real work" case specifically, not
    # any ticket where before-review usage is merely smaller than
    # during-review usage (that pattern alone is normal and expected, not
    # a sign PreReviewDays is unreliable - e.g. a ticket with 2.5 hours
    # before review and 143 hours during review is NOT this case; only a
    # near-total absence of before-review usage combined with substantial
    # during-review usage triggers the fallback).
    #
    # Uses ExpectedMinDays specifically (not the midpoint or max) as a
    # deliberately conservative baseline: if you beat the FASTEST-case
    # estimate, that's a guaranteed minimum saving - the true estimate
    # could have been anywhere in the range, so this never overstates it.
    # Zero (not negative) if the range wasn't beaten - "saved" doesn't
    # apply when it took as long as, or longer than, even the minimum.
    #
    # PreReviewDays is now business days (weekends excluded), computed
    # via Get-BusinessDaysElapsed - previously $preReviewHours / 24.0,
    # which counted weekends in full. See .NOTES ON Business-day
    # calculation above. This directly fixes the real case that
    # prompted it: someone working Friday, then Monday/Tuesday after a
    # weekend on leave, was previously shown as ~4 raw calendar days
    # instead of the correct ~3 business days.
    $preReviewDays = if ($reviewTransition) { [Math]::Round((Get-ActiveBusinessDaysElapsed -Transitions $transitions -Start $completionWindowStart -End $reviewTransition -ActiveStatuses @($InProgressStatus, $ReviewStatus) -Now ([DateTimeOffset]::UtcNow)), 2) } else { "" }
    $daysSaved = ""
    $pctSaved = ""
    $hoursSaved = ""
    $storyPointsSaved = ""
    $savedBasis = ""
    $completionDaysUsed = ""
    $completionHours = ""
    # Explicit flag, set true only where $hoursSaved is genuinely computed
    # below - deliberately not inferred via "$hoursSaved -ne ''" later on.
    # That comparison already caused a real bug once in this same script
    # (comparing a genuine 0 against "" coerces unpredictably in
    # PowerShell) - using an explicit flag here avoids repeating it.
    $hoursSavedComputed = $false

    # Guards on $reviewTransition existing (a clean truthy check) AND on
    # both hours values genuinely being doubles (-is [double]), not the ""
    # placeholder - NOT on comparing them against "" directly. A real bug
    # in an earlier version: when ClaudeHoursBeforeReview is a genuine 0
    # (a double, not the "" placeholder), PowerShell's -ne "" comparison
    # coerces types unpredictably between a number and a string, and
    # silently evaluated as false - meaning this check never fired for
    # exactly the real-zero case it was built to catch. -is [double] has
    # no such ambiguity: it's either genuinely a double, or it isn't.
    # Uses the explicit $beforeReviewComputed/$duringReviewComputed flags
    # set above - NOT type or value inference on the numbers themselves.
    # Two earlier versions of this check both tried to infer "was this
    # genuinely computed" from the value (first -ne "", then -is [double])
    # and neither reliably worked in practice. Tracking success explicitly,
    # at the exact point each computation succeeds, removes that entire
    # category of doubt.
    $reviewTooEarlyToBeMeaningful = ($beforeReviewComputed -and $duringReviewComputed -and $claudeHoursBeforeReview -lt 0.1 -and $claudeHoursDuringReview -gt 1)

    # Guards on $reviewTransition existing (a clean truthy check on a
    # DateTimeOffset), NOT on "$preReviewDays -ne ''" - a real bug found
    # alongside GGLOBDRA-2013: when a ticket flips into review within the
    # same minute it starts, PreReviewDays rounds to exactly 0.0, and
    # PowerShell's "0.0 -ne ''" evaluates to $false (confirmed directly),
    # so this branch was silently skipped for the exact near-zero case it
    # exists to handle - the same class of coercion bug the comment above
    # ($hoursSavedComputed) already documents and avoids for other fields.
    if ($reviewTransition -and -not $reviewTooEarlyToBeMeaningful) {
        $completionDaysUsed = $preReviewDays
        $savedBasis = "review"
    } elseif ($actualDays -ne "" -and -not $stillOpen) {
        $completionDaysUsed = $actualDays
        if ($reviewTooEarlyToBeMeaningful) {
            $savedBasis = "full-lifecycle (review transition too early to be meaningful - real work happened during review, not before it)"
        } else {
            $savedBasis = "full-lifecycle (no '$ReviewStatus' transition found)"
        }
    }
    if ($savedBasis -and $completionWindowStart -gt $windowStart) {
        # See .NOTES ON assignee-based completion window - $completionWindowStart
        # was clipped forward from $windowStart because the ticket's final
        # assignee only took ownership partway through its lifecycle.
        $savedBasis = "$savedBasis (measured from $completionWindowStart, when the ticket's final assignee took it over - not $windowStart, the ticket's first '$InProgressStatus')"
    }
    if ($completionDaysUsed -ne "") {
        # Same basis as DaysSaved below (review-to-date if that transition
        # exists, else full lifecycle) - kept as its own field so the
        # one-line ticket summary can state "finished in X hrs" using
        # exactly the same number DaysSaved/HoursSaved were computed
        # against.
        #
        # Uses $HoursPerDay here, NOT a hardcoded 24 - an earlier version
        # used 24 (real calendar hours), while HoursSaved below already
        # used $HoursPerDay (default 8, a workday-equivalent conversion).
        # That meant "finished in X hrs" and "saving Y hrs" were silently
        # on two different hour-per-day bases in the same sentence, even
        # though they read as directly comparable. Using $HoursPerDay for
        # both makes the whole sentence internally consistent: expected
        # (ExpectedMinDays * HoursPerDay) minus actual (this field) always
        # equals HoursSaved exactly, with no unit mismatch.
        $completionHours = [Math]::Round($completionDaysUsed * $HoursPerDay, 2)
    }
    if ($completionDaysUsed -ne "" -and $expectedMinDays -ne "") {
        # No longer clamped to 0 when the estimate wasn't beaten - a
        # negative value here is deliberate and informative (e.g. -6.14
        # days means it took 6.14 days LONGER than the fastest-case
        # estimate), not an error. Hiding overruns as a flat 0 obscured
        # exactly how far over a bad estimate a ticket actually went.
        $daysSaved = [Math]::Round($expectedMinDays - $completionDaysUsed, 2)
        $pctSaved = [Math]::Round(($daysSaved / $expectedMinDays) * 100, 1)

        # Hours saved: a direct unit conversion, days -> hours.
        $hoursSaved = [Math]::Round($daysSaved * $HoursPerDay, 2)
        $hoursSavedComputed = $true

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

    # Single, clean ticket-wide token total - main window tokens SUMMED
    # ACROSS EVERY REPO the ticket touched (not per-repo), plus the
    # pre-review/during-review/post-closure phases computed above. Shown
    # IDENTICALLY on every repo row further below, exactly like
    # TotalClaudeHours/TotalCostUsd already do - see the .NOTES ON
    # TotalTokensAllPhases section above for why a per-repo version of
    # this was wrong.
    #
    # Also breaks this down by type (input/output/cache_read/cache_creation)
    # - see the .NOTES ON Token breakdown section above for why this
    # matters: cache_read_tokens usually dominates the total by a wide
    # margin, but is priced at 0.1x normal input rate, so a bare total
    # token count alone can look alarmingly large relative to actual cost.
    $mainWindowTokens = 0
    $totalInputTokens = 0
    $totalOutputTokens = 0
    $totalCacheReadTokens = 0
    $totalCacheCreationTokens = 0
    foreach ($resultSet in @($result, $preReviewResult, $duringReviewResult, $postClosureResult)) {
        if ($resultSet -and $resultSet.hits) {
            foreach ($h in $resultSet.hits) {
                $totalInputTokens += (Get-SafeSum -Objects @($h) -Property "input_tokens")
                $totalOutputTokens += (Get-SafeSum -Objects @($h) -Property "output_tokens")
                $totalCacheReadTokens += (Get-SafeSum -Objects @($h) -Property "cache_read_tokens")
                $totalCacheCreationTokens += (Get-SafeSum -Objects @($h) -Property "cache_creation_tokens")
            }
        }
    }
    if ($result.hits) {
        foreach ($h in $result.hits) {
            $mainWindowTokens += ($h.input_tokens + $h.output_tokens + $h.cache_read_tokens + $h.cache_creation_tokens)
        }
    }
    $totalTokensAllPhases = $mainWindowTokens + $tokensReviewPhases

    if ($result.hits.Count -eq 0) {
        $note = if ($stillOpen) { "No usage found (still open, measured through now)" } else { "No usage found in window" }

        # Fall back to whichever repo(s) real activity was actually found
        # in (pre-review/during-review/post-closure), rather than leaving
        # Repo blank when we genuinely know where the work happened - the
        # main window having zero hits doesn't mean no repo is known, it
        # just means none of the activity fell inside THIS SPECIFIC window.
        $fallbackRepos = @()
        foreach ($otherResult in @($preReviewResult, $duringReviewResult, $postClosureResult)) {
            if ($otherResult -and $otherResult.hits) {
                foreach ($h in $otherResult.hits) {
                    if ($h.repo_name -and ($fallbackRepos -notcontains $h.repo_name)) {
                        $fallbackRepos += $h.repo_name
                    }
                }
            }
        }

        if ($fallbackRepos.Count -eq 0) {
            $report += New-ReportRow -TicketKey $ticketKey -PromptsAsked $promptsAskedCount -InProgressAt $windowStart -ClosedAt $stillOpenLabel -LifecycleHours $lifecycleHours -InProgressHours $inProgressHours `
                -ReviewAt $reviewTransition -PreReviewHours $preReviewHours -ClaudeHoursBeforeReview $claudeHoursBeforeReview -PctUsedBeforeReview $pctUsedBeforeReview `
                -DuringReviewHours $duringReviewHours -ClaudeHoursDuringReview $claudeHoursDuringReview -CostBeforeReview $costBeforeReview -CostDuringReview $costDuringReview -PostClosureHours $postClosureHours -ClaudeHoursPostClosure $claudeHoursPostClosure -CostPostClosure $costPostClosure -TotalClaudeHours $totalClaudeHours -TotalUsagePct $totalUsagePct -TotalCostUsd $totalCostUsd -TotalTokensAllPhases $totalTokensAllPhases -TotalInputTokens $totalInputTokens -TotalOutputTokens $totalOutputTokens -TotalCacheReadTokens $totalCacheReadTokens -TotalCacheCreationTokens $totalCacheCreationTokens `
                -StoryPoints $storyPoints -ExpectedMinDays $expectedMinDays -ExpectedMaxDays $expectedMaxDays -ActualDays $actualDays -Verdict $verdict `
                -PreReviewDays $preReviewDays -DaysSaved $daysSaved -PctSaved $pctSaved -HoursSaved $hoursSaved -StoryPointsSaved $storyPointsSaved -SavedBasis $savedBasis -CompletionHours $completionHours -Note $note
        } else {
            foreach ($repoName in $fallbackRepos) {
                $report += New-ReportRow -TicketKey $ticketKey -Repo $repoName -PromptsAsked $promptsAskedCount -InProgressAt $windowStart -ClosedAt $stillOpenLabel -LifecycleHours $lifecycleHours -InProgressHours $inProgressHours `
                    -ReviewAt $reviewTransition -PreReviewHours $preReviewHours -ClaudeHoursBeforeReview $claudeHoursBeforeReview -PctUsedBeforeReview $pctUsedBeforeReview `
                    -DuringReviewHours $duringReviewHours -ClaudeHoursDuringReview $claudeHoursDuringReview -CostBeforeReview $costBeforeReview -CostDuringReview $costDuringReview -PostClosureHours $postClosureHours -ClaudeHoursPostClosure $claudeHoursPostClosure -CostPostClosure $costPostClosure -TotalClaudeHours $totalClaudeHours -TotalUsagePct $totalUsagePct -TotalCostUsd $totalCostUsd -TotalTokensAllPhases $totalTokensAllPhases -TotalInputTokens $totalInputTokens -TotalOutputTokens $totalOutputTokens -TotalCacheReadTokens $totalCacheReadTokens -TotalCacheCreationTokens $totalCacheCreationTokens `
                    -StoryPoints $storyPoints -ExpectedMinDays $expectedMinDays -ExpectedMaxDays $expectedMaxDays -ActualDays $actualDays -Verdict $verdict `
                    -PreReviewDays $preReviewDays -DaysSaved $daysSaved -PctSaved $pctSaved -HoursSaved $hoursSaved -StoryPointsSaved $storyPointsSaved -SavedBasis $savedBasis -CompletionHours $completionHours -Note "$note (repo from pre/during-review/post-closure activity, not the main window)"
            }
        }
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
                -DuringReviewHours $duringReviewHours -ClaudeHoursDuringReview $claudeHoursDuringReview -CostBeforeReview $costBeforeReview -CostDuringReview $costDuringReview -PostClosureHours $postClosureHours -ClaudeHoursPostClosure $claudeHoursPostClosure -CostPostClosure $costPostClosure -TotalClaudeHours $totalClaudeHours -TotalUsagePct $totalUsagePct -TotalCostUsd $totalCostUsd -TotalTokensAllPhases $totalTokensAllPhases -TotalInputTokens $totalInputTokens -TotalOutputTokens $totalOutputTokens -TotalCacheReadTokens $totalCacheReadTokens -TotalCacheCreationTokens $totalCacheCreationTokens `
                -StoryPoints $storyPoints -ExpectedMinDays $expectedMinDays -ExpectedMaxDays $expectedMaxDays -ActualDays $actualDays -Verdict $verdict `
                -PreReviewDays $preReviewDays -DaysSaved $daysSaved -PctSaved $pctSaved -HoursSaved $hoursSaved -StoryPointsSaved $storyPointsSaved -SavedBasis $savedBasis -CompletionHours $completionHours -Note $note
        }
    }

    if ($PushToOpenObserve -and $hoursSavedComputed) {
        $summary = @{
            ticket             = $ticketKey
            story_points       = $storyPoints
            expected_min_days  = $expectedMinDays
            expected_max_days  = $expectedMaxDays
            completion_hours   = $completionHours
            hours_saved        = $hoursSaved
            story_points_saved = $storyPointsSaved
            pct_saved          = $pctSaved
            saved_basis        = $savedBasis
            verdict            = $verdict
            total_claude_hours = $totalClaudeHours
            total_cost_usd     = $totalCostUsd
            report_run_at      = [DateTimeOffset]::UtcNow.ToString("o")
        }
        Send-TicketSummaryToOpenObserve -Summary $summary
    }
}

Write-Host "`n=== Report ==="
$report | Format-Table -AutoSize -Property `
    Ticket, `
    Repo, `
    @{Label = "PromptsAsked"; Expression = { $_.PromptsAsked } }, `
    #@{Label = "Total Tokens"; Expression = { Format-BigNumber $_.TotalTokensAllPhases } }, `
    @{Label = "Input Token"; Expression = { Format-BigNumber $_.TotalInputTokens } }, `
    #@{Label = "Output"; Expression = { Format-BigNumber $_.TotalOutputTokens } }, `
    #@{Label = "CacheRead"; Expression = { Format-BigNumber $_.TotalCacheReadTokens } }, `
    #@{Label = "CacheCreate"; Expression = { Format-BigNumber $_.TotalCacheCreationTokens } }, `

    @{Label = "Total Hrs Actual Work"; Expression = { $_.TotalClaudeHours } }, `
    @{Label = "Total Cost USD"; Expression = { $_.TotalCostUsd } }, `
    #@{Label = "Post-Closure Hrs"; Expression = { $_.ClaudeHoursPostClosure } }, `
    #@{Label = "Post-Closure Cost"; Expression = { $_.CostPostClosure } }, `
    @{Label = "Hrs Saved"; Expression = { $_.HoursSaved } }, `
    #@{Label = "% Saved"; Expression = { $_.PctSaved } } `
    @{Label = "Story Point Saved"; Expression = { $_.StoryPointsSaved } } `
    | Out-String -Width 300 | Write-Host

# One plain-English line per ticket, using a group so a multi-repo ticket
# only prints once (not once per repo row) - StoryPoints/CompletionHours/
# HoursSaved/StoryPointsSaved are ticket-level values already duplicated
# identically across every repo row, so the first row per ticket is
# sufficient. Skipped for a ticket if any of these are missing (e.g. no
# story points on the ticket, or no completion basis found) rather than
# printing a sentence with blank gaps in it.
# Explicitly initialized to 0, not left to default to $null - PowerShell's
# $null + 5 does evaluate to 5, but being explicit here avoids any doubt,
# especially after the real $null/type-comparison bugs found elsewhere in
# this script.
$runTotalHoursSaved = 0.0
$runTotalStoryPointsSaved = 0.0
$runTotalUpperBoundHoursSaved = 0.0
$runTotalUpperBoundStoryPointsSaved = 0.0
$runTotalWorkHoursSavedLower = 0.0
$runTotalWorkHoursSavedUpper = 0.0
$runTotalWorkSPSavedLower = 0.0
$runTotalWorkSPSavedUpper = 0.0
$runTotalPromptsAsked = 0
$runTotalCostUsd = 0.0

foreach ($ticketGroup in ($report | Group-Object Ticket)) {
    $r = $ticketGroup.Group[0]

    # Accumulate across every ticket in this run, for the overall summary
    # line printed after this loop - blank values (not computed for this
    # ticket) contribute 0 rather than breaking the sum, same convention
    # as everywhere else in this script that treats "" as "nothing to
    # add here" rather than a genuine zero.
    #
    # Uses try/catch + explicit [double] cast, NOT "-is [double]" - an
    # earlier version used -is and silently failed for StoryPointsSaved/
    # TotalCostUsd specifically (while working for HoursSaved on the very
    # same row) - genuinely inconsistent behavior across fields that are
    # all built the same way, and not worth chasing the exact PowerShell
    # internals further. [double]"" reliably throws (blank correctly
    # skipped), and any genuine number converts successfully regardless
    # of its exact underlying type - this doesn't depend on guessing
    # what type a value happens to already be.
    try { $runTotalHoursSaved += [double]$r.HoursSaved } catch {}
    try { $runTotalStoryPointsSaved += [double]$r.StoryPointsSaved } catch {}
    try { $runTotalPromptsAsked += [int]$r.PromptsAsked } catch {}
    try { $runTotalCostUsd += [double]$r.TotalCostUsd } catch {}

    if ($r.StoryPoints -and $r.ExpectedMinDays -ne "" -and $r.ExpectedMaxDays -ne "" -and $r.CompletionHours -ne "" -and $r.HoursSaved -ne "" -and $r.StoryPointsSaved -ne "") {
        $spDisplay = "{0:F1}" -f [double]$r.StoryPoints
        # Verb depends on SavedBasis - "finished"/"closed" would be wrong
        # when the basis is "review" (this only measures time to reach
        # "Under Review", not actual closure - see .NOTES ON DaysSaved).
        # "work-hrs" (not just "hrs") makes clear these are a work-hour
        # equivalent of elapsed calendar time (CompletionDays * HoursPerDay),
        # not real elapsed hours and not actual Claude usage hours - that's
        # the separate sentence below.
        $stage = if ($r.SavedBasis -eq "review") { "reached review" } else { "was fully closed" }

        # HoursSaved/StoryPointsSaved compare against ExpectedMinDays
        # specifically (the fastest-case estimate), NOT the whole range -
        # a ticket can be comfortably "within" its overall estimate
        # (Verdict) while still showing a negative figure here, simply
        # because it didn't beat the best-case scenario. Naming Verdict
        # explicitly, and phrasing this as "beating"/"missing" the
        # fastest-case baseline rather than always "saving" (which reads
        # oddly, even misleadingly, for a negative number sitting right
        # next to "within range") makes that distinction clear rather
        # than looking like two numbers are contradicting each other.
        $verdictDisplay = ($r.Verdict -replace " \(still open.*\)", "")
        $fastestCaseVerb = if ([double]$r.HoursSaved -ge 0) { "beating" } else { "missing" }

        # Supplementary remark showing the SAME comparison against the
        # upper bound (ExpectedMaxDays) instead of the lower bound - shown
        # as an explicit subtraction so it's self-verifying, not just
        # another unexplained number. NOT the same ratio as
        # StoryPointsSaved above: that one scales by
        # (StoryPoints / ExpectedMinDays), which happens to be 1 for the
        # shipped story-points.yaml (5 points / 5 min-days). Here it's
        # (StoryPoints / ExpectedMaxDays) instead - for a 5-10 day range,
        # that's 5/10 = 0.5, genuinely different from the lower-bound
        # ratio, not a copy-paste of it.
        $maxWorkHrs = [double]$r.ExpectedMaxDays * $HoursPerDay
        $upperBoundHoursSaved = [Math]::Round($maxWorkHrs - [double]$r.CompletionHours, 2)
        $upperBoundStoryPointsSaved = [Math]::Round(($maxWorkHrs - [double]$r.CompletionHours) / $HoursPerDay * ([double]$r.StoryPoints / [double]$r.ExpectedMaxDays), 2)
        $runTotalUpperBoundHoursSaved += $upperBoundHoursSaved
        $runTotalUpperBoundStoryPointsSaved += $upperBoundStoryPointsSaved
        # Upper-bound percentage - same idea as the already-existing
        # PctSaved field (which is against ExpectedMinDays), just against
        # ExpectedMaxDays instead, matching the upper-bound remark's own basis.
        $upperBoundPct = [Math]::Round(($upperBoundHoursSaved / $maxWorkHrs) * 100, 1)
        $upperBoundRemark = " (against the upper-bound estimate: $maxWorkHrs - $($r.CompletionHours) = $upperBoundHoursSaved work-hrs / $upperBoundStoryPointsSaved story points [scaled at $($r.StoryPoints)pt-per-$($r.ExpectedMaxDays)d, not a plain hrs/8 conversion] / $upperBoundPct% still saved)"

        Write-Host "$($r.Ticket) with story point $spDisplay ($($r.ExpectedMinDays) - $($r.ExpectedMaxDays) days) $stage in $($r.CompletionHours) work-hrs - $verdictDisplay its overall estimate, while $fastestCaseVerb the fastest-case ($($r.ExpectedMinDays)-day / $([double]$r.ExpectedMinDays * $HoursPerDay)-work-hr) baseline by $([Math]::Abs([double]$r.HoursSaved)) work-hrs ($([Math]::Abs([double]$r.StoryPointsSaved)) story points / $([Math]::Abs([double]$r.PctSaved))%)$upperBoundRemark."
    }

    # Separate sentence, deliberately - this answers "how much was Claude
    # actually used", which is a different question from the "saved"
    # sentence above (that one is purely calendar-time vs. estimate, with
    # no connection to Claude usage at all - see .NOTES ON DaysSaved).
    # Skipped if these aren't available (e.g. no "Under Review" transition
    # found, so TotalClaudeHours/TotalCostUsd were never computed).
    if ($r.TotalClaudeHours -ne "" -and $r.TotalCostUsd -ne "") {
        $tokensDisplay = Format-BigNumber $r.TotalTokensAllPhases
        Write-Host "`n$($r.Ticket) used Claude for $($r.TotalClaudeHours) hrs, across $($r.PromptsAsked) prompt$(if ($r.PromptsAsked -ne 1) {'s'}), consuming $tokensDisplay tokens, at a cost of `$$($r.TotalCostUsd)."

        # A third, deliberately separate comparison: actual Claude WORK
        # hours against the estimate - not CompletionHours (how fast the
        # ticket's STATUS reached review/closure), which the two sentences
        # above already cover. Built because a real ticket showed exactly
        # why the distinction matters: status reached "Under Review" in
        # 1.28 hrs (looking like a huge saving against the estimate), but
        # TotalClaudeHours was 14.295 - almost the entire 16-hr lower-bound
        # estimate on its own, since most real work happened AFTER the
        # status changed, not before it. This answers "did the actual
        # work take less time than estimated", a genuinely different
        # question from "did the ticket's status change quickly".
        if ($r.ExpectedMinDays -ne "" -and $r.ExpectedMaxDays -ne "" -and $r.StoryPoints) {
            $lowerWorkHrs = [double]$r.ExpectedMinDays * $HoursPerDay
            $upperWorkHrs = [double]$r.ExpectedMaxDays * $HoursPerDay
            $workHoursSavedLower = [Math]::Round($lowerWorkHrs - [double]$r.TotalClaudeHours, 2)
            $workHoursSavedUpper = [Math]::Round($upperWorkHrs - [double]$r.TotalClaudeHours, 2)
            $workSPSavedLower = [Math]::Round($workHoursSavedLower / $HoursPerDay * ([double]$r.StoryPoints / [double]$r.ExpectedMinDays), 2)
            $workSPSavedUpper = [Math]::Round($workHoursSavedUpper / $HoursPerDay * ([double]$r.StoryPoints / [double]$r.ExpectedMaxDays), 2)
            $workPctLower = [Math]::Round(($workHoursSavedLower / $lowerWorkHrs) * 100, 1)
            $workPctUpper = [Math]::Round(($workHoursSavedUpper / $upperWorkHrs) * 100, 1)

            $runTotalWorkHoursSavedLower += $workHoursSavedLower
            $runTotalWorkHoursSavedUpper += $workHoursSavedUpper
            $runTotalWorkSPSavedLower += $workSPSavedLower
            $runTotalWorkSPSavedUpper += $workSPSavedUpper

            Write-Host "$($r.Ticket)'s actual Claude WORK ($($r.TotalClaudeHours) hrs) vs. estimate: $lowerWorkHrs - $($r.TotalClaudeHours) = $workHoursSavedLower hrs saved ($workSPSavedLower story points / $workPctLower%) against the lower-bound ($($r.ExpectedMinDays)-day) estimate; $upperWorkHrs - $($r.TotalClaudeHours) = $workHoursSavedUpper hrs saved ($workSPSavedUpper story points / $workPctUpper%) against the upper-bound ($($r.ExpectedMaxDays)-day) estimate."
        }
    }
}

# Overall totals across every ticket in this run - a batch of 20 tickets
# gets one combined figure here, not just 20 separate per-ticket lines
# above. Rounded only at print time - the accumulators themselves keep
# full precision throughout the loop. Table format, matching the main
# report above, rather than prose - two rows (Lower/Upper Bound) since
# HoursSaved/StoryPointsSaved differ by bound; PromptsAsked/TotalCost
# don't (they're actual totals, not estimate comparisons), so they
# repeat identically on both rows rather than being split out.
Write-Host "`n=== Run Totals ==="
@(
    [PSCustomObject]@{
        Bound                 = "Lower (fastest-case)"
        "Hrs Saved"           = [Math]::Round($runTotalHoursSaved, 2)
        "Story Points Saved"  = [Math]::Round($runTotalStoryPointsSaved, 2)
        "Prompts Asked"       = $runTotalPromptsAsked
        "Total Cost USD"      = [Math]::Round($runTotalCostUsd, 2)
    },
    [PSCustomObject]@{
        Bound                 = "Upper (worst-case)"
        "Hrs Saved"           = [Math]::Round($runTotalUpperBoundHoursSaved, 2)
        "Story Points Saved"  = [Math]::Round($runTotalUpperBoundStoryPointsSaved, 2)
        "Prompts Asked"       = $runTotalPromptsAsked
        "Total Cost USD"      = [Math]::Round($runTotalCostUsd, 2)
    }
) | Format-Table -AutoSize | Out-String -Width 300 | Write-Host

# Separate table, deliberately - "status reached review/closed quickly"
# (above) and "actual Claude work took less time than estimated" (here)
# are genuinely different questions, and a ticket can score very
# differently on each (see the sentence above this table for why).
Write-Host "=== Run Totals (Actual Claude Work vs. Estimate) ==="
@(
    [PSCustomObject]@{
        Bound                 = "Lower (fastest-case)"
        "Hrs Saved"           = [Math]::Round($runTotalWorkHoursSavedLower, 2)
        "Story Points Saved"  = [Math]::Round($runTotalWorkSPSavedLower, 2)
    },
    [PSCustomObject]@{
        Bound                 = "Upper (worst-case)"
        "Hrs Saved"           = [Math]::Round($runTotalWorkHoursSavedUpper, 2)
        "Story Points Saved"  = [Math]::Round($runTotalWorkSPSavedUpper, 2)
    }
) | Format-Table -AutoSize | Out-String -Width 300 | Write-Host

# Everything below is commented out, not removed - all of these fields
# are still computed and written to the CSV regardless of what's shown
# on screen. Uncomment (and move) any of these back into the -Property
# list above if you want them visible in the console again:
#     StoryPoints
#     ActualDays
#     InProgressToReviewDays (PreReviewDays)
#     input_tokens (InputTokens)
#     Total Tokens breakdown (TotalInputTokens, TotalOutputTokens, TotalCacheReadTokens, TotalCacheCreationTokens)
#     Hrs Before Review (ClaudeHoursBeforeReview)
#     Cost Before Review (CostBeforeReview)
#     Hrs During Review (ClaudeHoursDuringReview)
#     Cost During Review (CostDuringReview)
#     TotalClaudeHours
#     Claude Usage % (TotalUsagePct)
#     Days Saved (DaysSaved)
#     Saved % (PctSaved)
#     Post-Closure Hrs (ClaudeHoursPostClosure)
#     Post-Closure Cost (CostPostClosure)

try {
    $report | Export-Csv -Path $OutputCsv -NoTypeInformation
    Write-Host "`nFull details (all columns) written to $OutputCsv"
} catch {
    Write-Host "`nCouldn't write to '$OutputCsv': $($_.Exception.Message)"
    Write-Host "This usually means the file is already open in Excel or another program - close it and re-run, or pass a different -OutputCsv path. The report above was still computed correctly; only the CSV write failed."
}