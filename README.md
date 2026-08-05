# claude-history-ingestor — Phase 1

Personal engineering analytics platform over Claude Code's local history:
watches `.jsonl` session files, enriches and analyzes them, and ships
events to OpenObserve for dashboarding. This is **Phase 1 of 12** — see
the roadmap below.

## Phase 1 scope

Just the skeleton: configuration, a couple of REST endpoints, and a
`RestClient` bean pre-wired for OpenObserve (unused until Phase 6, but
set up now so later phases only add behavior).

**Classes in this phase:**
- `ClaudeHistoryApplication` — entry point
- `config/ClaudeProperties` — where to find Claude Code history files
- `config/OpenObserveProperties` — OpenObserve connection details
- `config/AppConfig` — shared beans (currently: a UTC `Clock`)
- `config/RestClientConfig` — `RestClient` bean, auth pre-configured
- `api/HealthController` — `GET /api/health`
- `api/ApplicationInfoController` — `GET /api/info`
- `model/VersionInfo` — payload for `/api/info`

## Requirements

- **Java 21** (Spring Boot 4.1 requires it)
- **Maven 3.9+**

## Build & run

```bash
mvn clean verify
mvn spring-boot:run
```

Then:

```bash
curl http://localhost:8080/api/health
# {"status":"UP"}

curl http://localhost:8080/api/info
# {"applicationName":"claude-history-ingestor","version":"0.1.0-SNAPSHOT","javaVersion":"21...","startedAt":"..."}

curl http://localhost:8080/actuator/health
# Spring Boot Actuator's own health check, also enabled
```

## Configuration

All of this lives in `src/main/resources/application.yml` and can be
overridden with environment variables — nothing is hardcoded:

| Property                  | Env var                | Default                              |
|---------------------------|-------------------------|----------------------------------------|
| `claude.history-path`     | `CLAUDE_HISTORY_PATH`   | `~/.claude/projects`                    |
| `claude.file-pattern`     | —                        | `*.jsonl`                               |
| `openobserve.base-url`    | `OPENOBSERVE_URL`       | `http://localhost:5080`                 |
| `openobserve.org`         | `OPENOBSERVE_ORG`       | `default`                               |
| `openobserve.stream`      | `OPENOBSERVE_STREAM`    | `claude_code_history`                   |
| `openobserve.user`        | `OPENOBSERVE_USER`      | *(empty — app still boots without it)*  |
| `openobserve.password`    | `OPENOBSERVE_PASSWORD`  | *(empty — app still boots without it)*  |
| `openobserve.batch-size`  | —                        | `500`                                    |

## A note on versions

This targets **Spring Boot 4.1.0** (current stable as of mid-2026), which
renamed several starters as part of its modularization — most notably
`spring-boot-starter-web` → `spring-boot-starter-webmvc`. If you're on an
older Spring Boot 3.x codebase elsewhere, don't copy these starter names
over directly; check the [official 4.0 migration guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide)
for the mapping.

I wasn't able to `mvn compile` this myself in the environment I built it
in (no Maven Central access there), so please run `mvn clean verify`
first thing and let me know if anything fails to resolve — quick to fix,
and better caught now than three phases in.

## Phase 2 scope

Recursively watches `claude.history-path` for files matching
`claude.file-pattern` and publishes a `FileChangeEvent` (via Spring's
`ApplicationEventPublisher`) for every discovered/created/modified/deleted
match. Also auto-detects project directories (`asset-search`,
`notification`, `terraform`, `customer-api`, ...) as it encounters them.

**No file content is read in this phase** — that's Phase 3 (offsets) and
Phase 4 (parsing). This phase only answers "something changed, here's the
path and which project."

**Classes in this phase** (`watcher` package):
- `ClaudeHistoryWatcher` — the `SmartLifecycle` bean that owns the
  `WatchService` loop
- `RecursiveWatchRegistrar` — registers a directory tree with the
  `WatchService` (Java's watch API isn't recursive by default, and doesn't
  auto-register new subdirectories — both cases go through here)
- `ProjectRegistry` — in-memory map of every project directory seen so far
- `ProjectDirectory` — record: name, path, discovered-at
- `FileChangeEvent` — record: file path, project name, kind, detected-at
- `FileChangeKind` — enum: `DISCOVERED`, `CREATED`, `MODIFIED`, `DELETED`
  (`DISCOVERED` is for files that already existed at startup, distinct
  from `CREATED` for files that appear while the watcher is running — this
  distinction will matter for Phase 3's offset logic)

### How Claude Code's files get mapped to a project

A file's project is the name of the first directory under
`claude.history-path` on its path — e.g.
`<root>/asset-search/session-1.jsonl` → project `asset-search`. Files
directly under the root (no subdirectory) fall back to project `_root`.

### Manually verifying Phase 2

There's no REST endpoint for this yet (that's Phase 9), so verify via the
console — `com.claude.ingestor` already logs at `DEBUG`:

```bash
# in one terminal
export CLAUDE_HISTORY_PATH=/tmp/claude-test
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

```bash
# in another terminal, after it's started and logged "Watching '...'"
echo '{"type":"user"}' > /tmp/claude-test/asset-search/session-1.jsonl
mkdir -p /tmp/claude-test/terraform
echo '{"type":"assistant"}' > /tmp/claude-test/terraform/session-1.jsonl
echo '{"type":"user"}' >> /tmp/claude-test/asset-search/session-1.jsonl
rm /tmp/claude-test/asset-search/session-1.jsonl
```

You should see, in order: an `INFO "Watching '/tmp/claude-test'..."` line
at startup (0 projects, since the directory was empty when you started
it), then `DEBUG` lines like:

```
CREATED /tmp/claude-test/asset-search/session-1.jsonl (project: asset-search)
DISCOVERED /tmp/claude-test/terraform/session-1.jsonl (project: terraform)
MODIFIED /tmp/claude-test/asset-search/session-1.jsonl (project: asset-search)
DELETED /tmp/claude-test/asset-search/session-1.jsonl (project: asset-search)
```

(`terraform/session-1.jsonl` shows as `DISCOVERED` rather than `CREATED`
because the watcher does a full walk of any brand-new directory the
moment it registers it — from the watcher's point of view a project that
shows up mid-run is handled the same as one that existed at startup.)

### Known limitation (by design, for now)

If `claude.history-path` doesn't exist when the app starts, the watcher
logs a warning and simply doesn't start — it doesn't retry on a timer.
Create the directory (or point `CLAUDE_HISTORY_PATH` at one that exists)
and restart. A background retry can be added later if it turns out to
matter in practice.

## Phase 3 scope

Remembers how far each file has been read, so a restart (or a burst of
append events on a multi-gigabyte session file) doesn't mean re-reading
from byte zero.

**No parsing happens in this phase either** — it still only deals in byte
offsets and file sizes. Phase 4 is where the actual JSONL content gets
read.

**Classes in this phase** (`offset` package):
- `OffsetStore` — interface: `getOffset`, `advanceOffset`, `remove`
- `PropertiesFileOffsetStore` — persists offsets to a flat, human-readable
  properties file (`/absolute/path.jsonl=1234` per line), with atomic
  writes (write-to-temp-then-rename) so a crash mid-write can't corrupt it
- `OffsetStoreProperties` — where that file lives (`claude.offset-store.path`)
- `NewContentAvailableEvent` — record: file, project, `[fromOffset, toOffset)`,
  detected-at
- `OffsetTrackingListener` — subscribes to Phase 2's `FileChangeEvent`,
  compares current file size to the last committed offset, and publishes
  `NewContentAvailableEvent` when there's something new

### A design note worth flagging

`OffsetTrackingListener` currently commits the offset **optimistically to
end-of-file** the moment it detects new bytes — not after anything has
actually parsed them (there's no parser yet; that's Phase 4). This is
called out explicitly in the Javadoc on `OffsetStore` and
`NewContentAvailableEvent` because it's a real correctness gap once a
parser exists: a `MODIFIED` event can fire while a line is still being
written, so "committed to file size" can land mid-line.

The plan for Phase 4: instead of the listener committing immediately,
the parser will consume `NewContentAvailableEvent`, read
`[fromOffset, toOffset)`, parse up to the last **complete** line, and
call `advanceOffset` itself with wherever it actually got to. I built
Phase 3 to commit eagerly for now specifically so it's independently
testable before that parser exists — flagging it now so it doesn't get
missed when we build Phase 4.

### Manually verifying Phase 3

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

In another terminal:

```bash
echo '{"type":"user"}' > /tmp/claude-test/asset-search/session-1.jsonl
echo '{"type":"assistant"}' >> /tmp/claude-test/asset-search/session-1.jsonl
```

You should see `DEBUG` lines like:

```
New content for '/tmp/claude-test/asset-search/session-1.jsonl': bytes [0, 18)
New content for '/tmp/claude-test/asset-search/session-1.jsonl': bytes [18, 42)
```

Stop the app (`Ctrl+C`) and inspect the offset file — it should show the
committed byte count:

```bash
cat /tmp/claude-test-offsets.properties
```

Restart the app: since nothing has changed on disk since the last run,
you should **not** see a `New content` line for that file this time
(only "No new bytes" at `DEBUG`) — confirming the offset survived the
restart.

## Phase 4 scope

Reads exactly the `[fromOffset, toOffset)` byte range that Phase 3's
`NewContentAvailableEvent` describes, in bounded-memory chunks (never
loading a whole multi-gigabyte file into memory regardless of how large
the range is), parses each complete line as JSON, and publishes
`ParsedLine` or `LineParseFailure` per line — one bad line doesn't stop
the rest of the file from being read.

**This is also where the offset-commit gap flagged in Phase 3 gets
closed.** `OffsetTrackingListener` no longer calls `advanceOffset` itself;
`JsonlParsingListener` does, using the position just after the last
*complete* line it actually parsed — so a line that's mid-write when a
`MODIFIED` event fires is simply left uncommitted until it's whole. I
validated this specific edge case (chunk-boundary-spanning lines,
multi-byte UTF-8, CRLF endings, and a deliberately incomplete trailing
line that gets completed on a later read) standalone before wiring it in
— see "Manually verifying Phase 4" below for the same scenario runnable
against the real app.

Still no domain modeling here — `ParsedLine.json` is a generic parsed
tree (`Map`/`List`/`String`/`Long`/`Double`/`Boolean`/`null`), not a
`ClaudeEvent`. That mapping is Phase 5.

**Classes in this phase:**
- `util/Json` — dependency-free JSON parser. Deliberately *not* Jackson,
  even though it's on the classpath: Spring Boot 4 ships Jackson 3, which
  renamed packages/groupId (`com.fasterxml.jackson.*` → `tools.jackson.*`)
  and changed several APIs. Rather than risk drift against an API I
  couldn't compile-verify here, this has zero dependencies.
- `parser/JsonlLineReader` — reads a byte range in bounded-memory chunks,
  splitting on raw `\n` bytes (safe for UTF-8 — `0x0A` never appears as a
  continuation byte) so multi-byte characters are never corrupted even
  when a chunk boundary falls inside one
- `parser/LineConsumer` — functional interface for the per-line callback
  (three args — text, start offset, end offset — hence not a stock
  `java.util.function` type)
- `parser/LineReadResult` — record: consumed-up-to offset, lines emitted,
  whether a trailing partial line was left
- `parser/ParsedLine` — record, published as a Spring event per
  successfully-parsed line
- `parser/LineParseFailure` — record, published per line that failed to
  parse (truncated raw text, so one pathological line can't blow up logs)
- `parser/ParserProperties` — `claude.parser.chunk-size-bytes` (default 1
  MiB) and `claude.parser.max-raw-line-length-logged` (default 2000)
- `parser/JsonlParsingListener` — the orchestrator: subscribes to
  `NewContentAvailableEvent`, reads, parses, publishes, and commits the
  offset

### Manually verifying Phase 4

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

In another terminal, write a line without a trailing newline (simulating
a write-in-progress), then complete it:

```bash
printf '{"type":"user","message":"hi"}\n{"type":"assistant","message":"incomple' \
  > /tmp/claude-test/asset-search/session-1.jsonl
```

You should see the first line parsed and published, and a `DEBUG` log
noting a trailing partial line — offset committed only up through the
first line, *not* through the incomplete second one:

```
Parsed 1 line(s) from '.../session-1.jsonl', committed offset 32
'.../session-1.jsonl' had a trailing partial line at offset 32 - left for next read
```

Now complete the second line:

```bash
printf 'te"}\n' >> /tmp/claude-test/asset-search/session-1.jsonl
```

You should see exactly one more line parsed (no duplication, no loss of
the earlier partial bytes) and the offset advance to end-of-file:

```
Parsed 1 line(s) from '.../session-1.jsonl', committed offset 65
```

Try a deliberately malformed line too:

```bash
echo 'not valid json' >> /tmp/claude-test/asset-search/session-1.jsonl
```

You should see a `WARN` log for the parse failure — and, importantly, the
app keeps running and the offset still advances past that line (it's
skipped, not retried forever).

## Phase 5 scope

Maps Phase 4's generic `ParsedLine.json` tree into a proper typed domain
model: `ClaudeEvent`. This is where the actual (unofficial, reverse-
engineered) Claude Code history schema gets encoded in types instead of
raw `Map` lookups scattered across later phases.

**Classes in this phase** (`model` package):
- `ClaudeEvent` — the top-level record: session/uuid/parent linkage,
  timestamps, the message (if any), summary text (if any), tool result,
  plus provenance (source file, project, byte range, raw line)
- `EventType` — `USER` / `ASSISTANT` / `SUMMARY` / `UNKNOWN`
- `Message` — role, model, normalized content blocks, token usage
- `MessageRole` — `USER` / `ASSISTANT` / `UNKNOWN`
- `ContentBlock` — **sealed** interface over `TextBlock`, `ToolUseBlock`,
  `ToolResultBlock`, `UnknownBlock` — a raw message's `content` is either
  a plain string or an array of typed blocks; the mapper normalizes both
  into this one list shape
- `TokenUsage` — input/output/cache-read/cache-creation token counts
- `ToolUseResult` — the record-level `toolUseResult` field (a sibling of
  `message`, not the same thing as a `ToolResultBlock` nested inside one)
- `ClaudeEventMapper` — the actual mapping logic, defensive at every level
- `ClaudeEventMappingListener` — subscribes to `ParsedLine`, calls the
  mapper, publishes `ClaudeEvent`

### Why `UNKNOWN` / sealed types instead of failing loudly

Claude Code's history format isn't an officially published schema, so
this project treats every "shape" question the same defensive way it has
since Phase 4's parser: an unrecognized `type`, a `content` block type
nobody's seen before, or even a line whose top-level JSON isn't an object
at all, all degrade to a best-effort `ClaudeEvent` (tagged `UNKNOWN`
where relevant) with the raw line preserved — never a crash, never a
silently dropped record. I validated exactly these fallback paths
standalone (unrecognized top-level `type`, unrecognized content-block
`type`, a top-level JSON array instead of an object) before wiring this
into Spring.

`ContentBlock` being **sealed** means a `switch` over
`TextBlock`/`ToolUseBlock`/`ToolResultBlock`/`UnknownBlock` in a later
phase gets compiler-checked exhaustiveness — if a fifth block type is
ever added, every such switch fails to compile until it's handled, rather
than silently falling through.

### Manually verifying Phase 5

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

In another terminal:

```bash
cat >> /tmp/claude-test/asset-search/session-1.jsonl << 'EOF'
{"type":"user","sessionId":"s1","uuid":"u1","timestamp":"2026-07-25T10:00:00Z","message":{"role":"user","content":"Hello"}}
{"type":"assistant","sessionId":"s1","uuid":"u2","message":{"role":"assistant","model":"claude-sonnet-5","content":[{"type":"text","text":"Hi there"},{"type":"tool_use","name":"Read","input":{"file":"main.py"}}],"usage":{"input_tokens":10,"output_tokens":5}}}
{"type":"a_future_record_type_nobody_recognizes_yet","sessionId":"s1"}
EOF
```

You should see:

```
Mapped USER event from '.../session-1.jsonl' (session s1)
Mapped ASSISTANT event from '.../session-1.jsonl' (session s1)
Mapped an UNKNOWN-type event from '.../session-1.jsonl' at [..., ...) - raw line preserved for inspection
```

The third line proves the "don't crash on schema drift" behavior: an
entirely unrecognized `type` still produces a usable event and keeps the
app running, rather than being dropped or throwing.

## Phase 6 scope

Finally puts Phase 1's pre-wired `RestClient` bean to use: batches
`ClaudeEvent`s and ships them to OpenObserve as OTLP logs, the same wire
format the standalone OTEL ingester tool (built earlier in this
conversation) used for one-shot batch imports — except this is event-
driven and live, firing as new history gets written rather than run once
over existing files.

**Classes in this phase** (`sender` package):
- `ClaudeEventToLogRecordMapper` — maps one `ClaudeEvent` to an OTLP
  `LogRecord` JSON fragment. Builds JSON by hand with `util.Json.quote`
  (which gained escaping/quoting helpers this phase - it was parse-only
  through Phase 4) rather than via Jackson, for the same reason as
  before: full control over the wire shape without depending on exact
  Jackson 3 API behavior I can't compile-verify here
- `OtlpPayloadBuilder` — wraps a batch of fragments into the full
  `resourceLogs` envelope
- `OpenObserveSender` — POSTs a batch via the Phase 1 `RestClient` bean.
  **Known gap, flagged on purpose:** a failed send is logged and the
  batch is dropped — no retry/backoff/dead-letter queue yet
- `OpenObserveBatchingListener` — subscribes to `ClaudeEvent`, queues it,
  and flushes on whichever comes first: `openobserve.batch-size` events
  queued, or `openobserve.flush-interval-ms` elapsed (so a slow trickle
  of events during an idle session doesn't sit unshipped indefinitely)

I validated the JSON-building, escaping, severity/attribute mapping, and
the drain-up-to-cap batching logic standalone before wiring any of it
into Spring — including a check that quotes and newlines in message text
get escaped correctly in the output.

### A real bug caught while wiring this phase in

While adding `@EnableScheduling` to `ClaudeHistoryApplication`, I noticed
`@ConfigurationPropertiesScan("com.claude.ingestor.config")` only scans
that one package — but `OffsetStoreProperties` (Phase 3) lives in
`com.claude.ingestor.offset` and `ParserProperties` (Phase 4) lives in
`com.claude.ingestor.parser`. Neither is a sub-package of `.config`, so
**neither has actually been registered as a Spring bean since the phase
it was introduced.** The app would have failed at startup with
`NoSuchBeanDefinitionException` the moment either was actually needed —
`mvn clean verify` never caught it because there are no tests yet that
boot the Spring context, only compilation.

Fixed by widening the scan to `@ConfigurationPropertiesScan` with no
argument, which defaults to the annotated class's own package
(`com.claude.ingestor`) and covers every sub-package recursively. If
Phases 3-5 seemed to work when you ran them manually, it's worth
double-checking now that it wasn't silently failing in a way you hadn't
hit yet — see the manual verification steps below, which now double as
confirmation this is actually fixed.

### Manually verifying Phase 6

You'll need a real (or throwaway) OpenObserve instance for this one,
since there's now an actual outbound call:

```bash
docker run -d --name openobserve -p 5080:5080 \
  -e ZO_ROOT_USER_EMAIL="root@example.com" \
  -e ZO_ROOT_USER_PASSWORD="Complexpass#123" \
  public.ecr.aws/zinclabs/openobserve:latest
```

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
export OPENOBSERVE_USER=root@example.com
export OPENOBSERVE_PASSWORD='Complexpass#123'
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

Confirm first that it **boots without a bean error** — that alone
confirms the fix above. Then, in another terminal:

```bash
cat >> /tmp/claude-test/asset-search/session-1.jsonl << 'EOF'
{"type":"user","sessionId":"s1","uuid":"u1","timestamp":"2026-07-25T10:00:00Z","message":{"role":"user","content":"Hello"}}
EOF
```

Within `openobserve.flush-interval-ms` (2 seconds by default — one test
event won't hit the 500-event batch-size threshold on its own), you
should see:

```
Sent batch of 1 event(s) to OpenObserve (org=default, stream=claude_code_history)
```

Then check the OpenObserve UI (http://localhost:5080) under the
`claude_code_history` stream for the event.

## Phase 7 scope

Enriches each event with a detected repo name and technology stack -
`pom.xml` → Java, `package.json` → React/Vue/Node, `*.tf` → Terraform,
etc - matching the roadmap's own examples.

**A design decision worth explaining:** the roadmap's example
(`C--code-asset-search` → `asset-search`) describes decoding Phase 2's
watcher-derived project folder name, which is a dash-encoded form of a
real filesystem path. I didn't implement that decoding, because it's
genuinely ambiguous, not just fiddly: the encoding replaces path
separators with `-`, but a real repo name can *also* contain `-` (like
`asset-search` itself, or `customer-api`) - so there's no way to tell,
after the fact, whether a dash in the encoded name was a path separator
or part of the actual name. Instead, this phase uses
`ClaudeEvent.cwd()`, the actual working-directory path Claude Code
already recorded for that session, which is a real, unambiguous
filesystem path with real separators. I validated this specifically -
`customer-api` (a repo name containing a dash) survives correctly as one
segment when derived from `cwd`, which wouldn't be guaranteed from the
encoded folder name.

**Classes in this phase** (`repository` package):
- `TechnologyDetector` — plugin interface: `technologyName()`, `matches(Path)`
- `JavaMavenDetector`, `JavaGradleDetector`, `TerraformDetector`, `GoDetector`,
  `PythonDetector` — marker-file detectors
- `NodeJsDetector` — matches on `package.json`, then `refine()` sniffs
  `dependencies`/`devDependencies` for `react`/`vue` to report something
  more specific than generic "Node.js" (using `util.Json` — no Jackson
  needed for this either)
- `RepositoryEnrichment` — record: repo name, detected technologies, when
- `RepositoryEnricher` — runs every `TechnologyDetector` bean against a
  directory, **cached** per directory (a repo's tech stack doesn't change
  message-to-message, so there's no reason to re-scan the filesystem on
  every single event)
- `EnrichedClaudeEvent` — pairs a `ClaudeEvent` with its `RepositoryEnrichment`
- `EnrichmentListener` — subscribes to `ClaudeEvent`, enriches, publishes
  `EnrichedClaudeEvent`

**Adding a new technology is meant to be trivial**: implement
`TechnologyDetector`, add `@Component`, done — `RepositoryEnricher`
auto-discovers every bean implementing the interface via
`List<TechnologyDetector>` injection. This directly supports the
"automatic engineering categorization" item from the enhancements list.

### Integration note: Phase 6 now consumes `EnrichedClaudeEvent`

`OpenObserveBatchingListener` switched from subscribing to `ClaudeEvent`
to `EnrichedClaudeEvent`, and `ClaudeEventToLogRecordMapper.toLogRecordJson`
now takes a `RepositoryEnrichment` parameter and adds `repo.name` and
`repo.technologies` attributes. Otherwise the enrichment data would be
computed and then just... discarded, never reaching OpenObserve.

**Known simplification, flagged rather than hidden:** `repo.technologies`
is a single comma-joined string attribute (e.g.
`"Java (Maven),Terraform"`), not a proper multi-value field. That's fine
for display but awkward for a `GROUP BY technology`-style dashboard query.
Worth revisiting in Phase 8 (analytics) or Phase 10 (dashboard SQL) once
there's a concrete query that needs it — OpenObserve's SQL has array/split
functions that could unnest this, or this could emit one row per
technology instead.

### Manually verifying Phase 7

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
mkdir -p /tmp/claude-test/asset-search
mkdir -p /tmp/test-repos/customer-api
echo '<project></project>' > /tmp/test-repos/customer-api/pom.xml
echo 'resource "aws_instance" "x" {}' > /tmp/test-repos/customer-api/main.tf
mvn spring-boot:run
```

In another terminal, write an event whose `cwd` points at that test repo
(note: **real** path, not the watched history path — `cwd` is Claude
Code's own working-directory field, unrelated to where its history files
live):

```bash
cat >> /tmp/claude-test/asset-search/session-1.jsonl << 'EOF'
{"type":"user","sessionId":"s1","uuid":"u1","cwd":"/tmp/test-repos/customer-api","timestamp":"2026-07-25T10:00:00Z","message":{"role":"user","content":"Hello"}}
EOF
```

You should see:

```
Enriched '/tmp/test-repos/customer-api' -> repo=customer-api, technologies=[Java (Maven), Terraform]
```

— correctly showing both technologies for a repo with both a `pom.xml`
*and* Terraform files, and preserving `customer-api` as one segment
(not truncating at its internal dash, the way decoding the encoded
folder name could have).

## Phase 8 scope

The analytics engine: the "today's prompts / today's cost / most active
repo / longest session / most expensive prompt / top language /
engineering score" rollups from the original enhancement list, computed
live from the `EnrichedClaudeEvent` stream Phase 7 produces.

**Classes in this phase** (`analytics` package):
- `PricingProperties` / `ModelPrice` — per-model USD-per-million-token
  pricing, fully configurable
- `CostCalculator` — estimates cost from token usage + model. Cache
  pricing is *approximated* (0.1x input for cache reads, 1.25x for
  5-minute cache writes) since Claude Code's transcripts don't record
  which cache TTL was actually used — documented as an approximation,
  not exact billing
- `PromptClassifier` — isolates one specific judgment call in one place:
  a `USER` event only counts as a "prompt" if it has an actual typed
  `TextBlock`, not just an automatic `tool_result` being fed back
- `SessionSummary`, `MostExpensivePrompt`, `AnalyticsSnapshot` — the
  immutable read-model records
- `EngineeringScoreWeights` / `AnalyticsProperties` — timezone (for what
  "today" means) and the score formula's tunable weights
- `EngineeringScoreCalculator` — **read the caveat below before trusting
  this number**
- `MetricsAccumulator` — the stateful engine: per-day rollups (prompts,
  cost, sessions, distinct repos/technologies, error rate) and all-time
  rollups (most active repo, longest session, most expensive prompt, top
  technology), all in-memory
- `AnalyticsEventListener` — thin bridge, all logic lives in the accumulator

### Scope decisions worth knowing about

**Today vs. all-time.** The roadmap listed "today's prompts / cost /
sessions" together, then "most active repo / longest session / most
expensive prompt / top language" separately — I read that as intentional
and implemented the first three as day-scoped, the rest as all-time.
Worth confirming that's actually what's wanted before this goes further.

**Timezone matters more than it looks.** The same instant can land on
different calendar dates depending on `claude.analytics.timezone` (23:30
UTC is already tomorrow in Tokyo) — I specifically validated this
boundary case standalone before wiring it in. Defaults to UTC; set it to
wherever you actually work if "today" should mean your local day.

**The engineering score is a heuristic, not a measurement — I want to be
upfront about that rather than let a 0-100 number imply more rigor than
exists.** There's no industry-standard definition of this; it's a simple
weighted sum (prompts, distinct repos, distinct technologies, minus an
error-rate penalty), and every weight is configurable specifically so it
can be tuned to what you actually value rather than trusted as shipped.
See `EngineeringScoreCalculator`'s Javadoc.

**Cost estimates use current Anthropic pricing, verified while writing
this** (not carried over from training data) — Claude Opus 4.8 at
$5/$25 per million tokens, Sonnet 5 at its current **introductory**
$2/$10 (reverting to standard $3/$15 on September 1, 2026 — the
`application.yml` comment flags this so it doesn't go stale silently),
Haiku 4.5 at $1/$5, Fable 5/Mythos 5 at $10/$50. Still worth checking
platform.claude.com/docs/en/about-claude/pricing before trusting a cost
figure for anything that matters, since rates do change.

**All state is in-memory** — a restart zeroes every metric. Fine for a
live "how's today going" view; would need persistence (or rebuilding from
OpenObserve query results) if historical trends across restarts matter.

### Manually verifying Phase 8

There's no REST endpoint yet (Phase 9), so this needs a temporary log
line or a debugger breakpoint on `MetricsAccumulator.snapshot()` to
actually see the numbers this phase — that's an intentional gap Phase 9
closes. What you *can* verify now via the existing `DEBUG` logs:

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

Confirm it boots without a bean/binding error — that's the first
meaningful check, given `PricingProperties`/`AnalyticsProperties` are new
`@ConfigurationProperties` classes in yet another package
(`.analytics`), exactly the kind of thing Phase 6's bug was about. Then
write a couple of events and confirm no exceptions surface from the new
`AnalyticsEventListener` / `MetricsAccumulator` chain reacting to them
(everything upstream still logs its own progress as before).

## Phase 9 scope

The five REST endpoints, exposing everything Phase 8's
`MetricsAccumulator` tracks:

| Endpoint | Returns |
| --- | --- |
| `GET /analytics/daily` | Today's prompts, cost, sessions, engineering score |
| `GET /analytics/repositories` | All-time per-repo breakdown: events, prompts, cost, last-active, technologies |
| `GET /analytics/models` | All-time per-model breakdown: events, input/output tokens, cost |
| `GET /analytics/cost?days=N` | Daily cost trend, last N days (default 30, clamped to [1, 365]), gap-filled with zeros so a chart doesn't need its own gap logic |
| `GET /analytics/activity` | All-time highlights: most active repo, longest session, most expensive prompt, top technology |

**Extending `MetricsAccumulator` rather than adding a separate query
layer.** The repositories/models endpoints needed per-entity breakdowns
(prompt count, cost, last-active timestamp, technologies per repo;
tokens and cost per model) that Phase 8 wasn't tracking — it only kept
enough state for the single daily snapshot. Added the tracking directly
to the existing accumulator (same `ConcurrentHashMap` + `LongAdder`/
`DoubleAdder` pattern throughout) rather than a second parallel
component, since it's the same event stream and the same "just count
things as they arrive" shape.

**Classes in this phase:**
- `RepoBreakdown`, `ModelBreakdown`, `DailyCostPoint`, `ActivityHighlights`,
  `DailyMetrics` — response records (`analytics` package)
- `AnalyticsController` — the five endpoints (`api` package)

Validated standalone before wiring in: last-active-timestamp tracking
(specifically, that an out-of-order *earlier* event can't overwrite a
later last-active timestamp — a real bug shape if done naively with plain
assignment instead of a max-merge), and the gap-filled day-range
generation for the cost trend (a day with zero activity must still
appear as a zeroed point, not be silently omitted, or a chart built on
top would misrender its x-axis).

### Manually verifying Phase 9

This finally closes the "no REST endpoint yet" gap flagged at the end of
Phase 8:

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

```bash
cat >> /tmp/claude-test/asset-search/session-1.jsonl << 'EOF'
{"type":"user","sessionId":"s1","uuid":"u1","cwd":"/tmp/test-repos/customer-api","timestamp":"2026-07-26T10:00:00Z","message":{"role":"user","content":"Hello"}}
{"type":"assistant","sessionId":"s1","uuid":"u2","cwd":"/tmp/test-repos/customer-api","message":{"role":"assistant","model":"claude-sonnet-5","content":[{"type":"text","text":"Hi"}],"usage":{"input_tokens":1000,"output_tokens":500}}}
EOF
```

Then:

```bash
curl -s http://localhost:8080/analytics/daily | python3 -m json.tool
curl -s http://localhost:8080/analytics/repositories | python3 -m json.tool
curl -s http://localhost:8080/analytics/models | python3 -m json.tool
curl -s http://localhost:8080/analytics/cost?days=7 | python3 -m json.tool
curl -s http://localhost:8080/analytics/activity | python3 -m json.tool
```

You should see `promptsToday: 1` (only the first event has actual typed
text — the second is an assistant response, not a prompt), a
`customer-api` entry in `/repositories`, a `claude-sonnet-5` entry in
`/models` with `inputTokens: 1000, outputTokens: 500` and a cost
reflecting the introductory Sonnet 5 rate, and `/cost?days=7` returning
exactly 7 points with only today's non-zero.

## Phase 10 scope

Dashboard SQL against the `claude_code_history` OpenObserve stream — see
**[`docs/dashboard-sql.md`](docs/dashboard-sql.md)** for all of it
(events over time, events by type, top tools, token usage over time,
cost over time, error rate, sessions timeline, repo activity, top
languages, most expensive exchanges, model usage breakdown).

**No new Java classes this phase** (matches the roadmap's own table,
which lists "—" for this phase's class count) — but two real changes to
`ClaudeEventToLogRecordMapper` were needed to make the SQL in that doc
actually work, rather than just writing speculative queries against
fields that don't exist:

1. **Added `llm.cost_usd`.** It didn't exist in the exported OTLP stream
   before this phase — `ClaudeEventToLogRecordMapper` now depends on
   Phase 8's `CostCalculator` specifically so a "cost over time" panel
   has something to query. Before this, cost was only ever visible
   through the app's own REST API (Phase 9), never in OpenObserve itself.
2. **Changed `repo.technologies` from comma-joined to a stringified JSON
   array** (`["Java (Maven)","Terraform"]` instead of
   `"Java (Maven),Terraform"`). This was flagged as a known
   simplification back in Phase 7, with a note to revisit "once there's
   a concrete query that needs it" — writing the "top languages" panel
   was exactly that moment. OpenObserve's array functions (`cast_to_arr`,
   `unnest`) only operate on the JSON-array shape.

**Verified rather than guessed: OpenObserve normalizes OTLP attribute
dots to underscores at ingest** (confirmed against OpenObserve's own
documentation on this specific behavior) — so `event.type` as emitted by
this app becomes `event_type` in SQL, `llm.cost_usd` becomes
`llm_cost_usd`, etc. Every query in the dashboard-sql doc already
accounts for this; it's called out explicitly there too since it's easy
to paste a query using dots and have it silently fail to find the field.

### Manually verifying Phase 10

```bash
export CLAUDE_HISTORY_PATH=/tmp/claude-test
export CLAUDE_OFFSET_STORE_PATH=/tmp/claude-test-offsets.properties
export OPENOBSERVE_USER=root@example.com
export OPENOBSERVE_PASSWORD='Complexpass#123'
mkdir -p /tmp/claude-test/asset-search
mvn spring-boot:run
```

```bash
cat >> /tmp/claude-test/asset-search/session-1.jsonl << 'EOF'
{"type":"assistant","sessionId":"s1","uuid":"u2","cwd":"/tmp/test-repos/customer-api","message":{"role":"assistant","model":"claude-sonnet-5","content":[{"type":"text","text":"Hi"}],"usage":{"input_tokens":1000,"output_tokens":500}}}
EOF
```

In the OpenObserve UI, open the `claude_code_history` stream's schema
browser and confirm `llm_cost_usd` and `repo_technologies` are present
with the expected shapes, then try the "Cost over time" and "Top
languages" queries from `docs/dashboard-sql.md` directly in the SQL
query editor before wiring them into an actual dashboard panel.

## Phase 11 scope

`docker compose up` brings up OpenObserve and this app together.

- **`Dockerfile`** — multi-stage: builds with the official
  `maven:3.9.9-eclipse-temurin-21` image (so the build doesn't depend on
  anything pre-installed on the host besides Docker itself), runs on a
  slim `eclipse-temurin:21-jre-jammy`, as a non-root user
- **`docker-compose.yml`** — OpenObserve + the ingestor, wired together
  with named volumes for both OpenObserve's data and the offset store
  (so restarting containers doesn't lose either)
- **`.env.example`** — copy to `.env` and fill in; `.env` is gitignored
  so real credentials never get committed, only the example

### A mistake I caught before it shipped

My first draft of `docker-compose.yml` defaulted the history-mount path
with `${CLAUDE_HISTORY_SOURCE:-${HOME}/.claude/projects}` - nested
variable substitution. I couldn't find this confirmed as supported
anywhere in Docker's own interpolation documentation, and didn't want to
ship something that looks plausible but might silently fail to expand
(the same category of mistake as `@DefaultValue("${user.home}/...")`
back in Phase 3). Fixed it to use the documented, verified `:?error`
syntax instead: `CLAUDE_HISTORY_SOURCE` is now **required** with no
default, and `docker compose up` fails with a clear, actionable message
if it's not set in `.env` — rather than silently mounting an empty or
wrong path.

### What I couldn't verify here

No Docker daemon is available in the environment I built this in, so
unlike every previous phase, **I could not actually run
`docker compose up` and confirm this works end-to-end.** I'm flagging
this more explicitly than usual because it's a bigger gap than earlier
phases' "couldn't compile Spring Boot" caveat — this is untested at the
level of "does the container even start." Please run it and report back
before trusting it:

```bash
cp .env.example .env
# edit .env: set CLAUDE_HISTORY_SOURCE to your real path
docker compose up --build
```

Things worth double-checking specifically, since I couldn't:
- That `mvn -B clean package -DskipTests` inside the build stage actually
  produces `target/claude-history-ingestor-*.jar` as an executable jar
  (it should, per how the `spring-boot-maven-plugin` is declared in
  `pom.xml` since Phase 1 - but "should" isn't "confirmed" here)
- That the OpenObserve image's environment variable names
  (`ZO_ROOT_USER_EMAIL`, `ZO_ROOT_USER_PASSWORD`) are still current -
  these were correct as of Phase 1's manual-setup instructions, carried
  forward here, but not re-verified against OpenObserve's current docs
  for this phase specifically
- That the ingestor container can actually resolve and reach
  `http://openobserve:5080` by service name (standard Compose networking
  behavior, but "standard" isn't "verified in this specific compose file")

There's also no container healthcheck for either service - `depends_on`
here only controls start *order*, not readiness. The ingestor may log a
few failed-batch errors (already-documented behavior since Phase 6 - no
retry yet) in the few seconds before OpenObserve finishes starting up.
That's a known, pre-existing limitation, not something new to Docker.

## Roadmap

| Phase | Description                      |
| ----- | --------------------------------- |
| 1     | Project skeleton + configuration ✅ |
| 2     | Recursive file watcher ✅          |
| 3     | Offset management ✅               |
| 4     | JSONL parser ✅                    |
| 5     | Claude event model ✅              |
| 6     | OpenObserve client ✅              |
| 7     | Event enrichment ✅                |
| 8     | Analytics engine ✅                |
| 9     | REST APIs ✅                       |
| 10    | Dashboard SQL ✅                   |
| 11    | Docker ✅ (this, unverified - see above) |
| 12    | Tests & documentation             |

## Post-Phase-11 addendum: `event.is_prompt`

While working through real dashboard queries against the running app
(see `docs/dashboard-sql.md`), it became clear there was no way to
filter the exported stream down to actual user-typed prompts, as opposed
to automatic `tool_result` records - the same gap `llm.cost_usd` and the
`repo.technologies` array-format fix closed in Phase 10, found the same
way: by trying to write a query that needed something the exporter
didn't have yet.

`ClaudeEventToLogRecordMapper` now attaches `event.is_prompt` using
Phase 8's `PromptClassifier` - the exact same logic the analytics engine
already used internally for "today's prompts." This means `GET
/analytics/daily`'s prompt count and any dashboard query filtering on
`event_is_prompt = true` are now guaranteed to agree, rather than the
dashboard needing its own separate (and possibly inconsistent)
definition of "prompt."

## Post-Phase-11 addendum: `repo_name` was wrong for Windows-sourced paths

Found from real production data (not a hypothetical): a Windows Claude
Code `cwd` like `C:\code\notification-template-terraform` was showing up
in OpenObserve as `repo_name: "C:\code\notification-template-terraform"`
- the **entire path**, not just `notification-template-terraform`.

The cause: `RepositoryEnricher` derived the repo name via
`java.nio.file.Path.getFileName()`, but `Path`'s separator handling
follows whatever OS the JVM itself is running on. This app runs inside a
**Linux** container (per Phase 11's `docker-compose.yml`), and Linux
`Path` only splits on `/` - it has no concept of `\` as a separator or
`C:` as a drive prefix, so a Windows-recorded `cwd` came back as one
single, opaque "path segment": the whole string.

Fixed by deriving `repoName` via plain string manipulation (replace `\`
with `/`, trim trailing separators, take the last segment) instead of
`Path` - this works correctly regardless of which OS recorded the `cwd`
or which OS this process happens to be running on. Validated against
the exact real-world path from the bug report
(`C:\dev\claude-metrics\claude-history-ingestor\docker` → `docker`)
plus Unix paths, trailing slashes, and a couple of edge cases, before
shipping the fix.

Technology detection (`pom.xml`, `package.json`, etc.) has a separate,
structural limitation worth knowing about while we're here: the Docker
deployment only mounts `CLAUDE_HISTORY_SOURCE` into the container, never
the actual project source trees a `cwd` points at (there's no practical
way to mount every repo someone might `cd` into in advance). So
`repo.technologies` will essentially always come back empty when running
via `docker compose`, even after this fix - that's expected, not a bug,
and `RepositoryEnricher`'s Javadoc now says so explicitly. `repo_name`
itself is unaffected, since it's derived from the `cwd` string alone and
needs no filesystem access.

**This only affects events ingested after the fix is deployed** - same
caveat as `event.is_prompt` above. Existing OpenObserve data keeps
whatever `repo_name` it already has.

Next up: Phase 12, tests & documentation - and given everything flagged
across the last four phases (the `@ConfigurationPropertiesScan` bug, no
`@SpringBootTest` anywhere, and now a whole Docker setup I couldn't
actually run), this is the phase I'd push back on deferring further if
you're inclined to. A `@SpringBootTest` that just boots the context would
have caught the Phase 6 bug immediately, automatically, on every future
change - which is exactly the coverage this project has been missing
since before it had a REST API, a Docker setup, or ten phases of things
that could quietly stop wiring together correctly.