# Quickstart

## 1. Start the Docker ingestor (reads your own Claude Code history)

From the folder containing `docker-compose.yml`:

1. Copy `.env.example` to `.env` and set two things:
   - `CLAUDE_HISTORY_SOURCE` → your own `~/.claude/projects` folder path
   - `ZO_ROOT_USER_EMAIL` / `ZO_ROOT_USER_PASSWORD` → any login you want for OpenObserve
2. Run:
   ```powershell
   docker compose up -d
   ```
3. Open http://localhost:5080, log in with the credentials from step 1.
   Give it ~15 seconds, then check **Streams → `claude_code_history`** has data.

## 2. Run the JIRA usage report (PowerShell)

From the `scripts/` folder:

1. One-time only - unblock the script so Windows stops warning about it:
   ```powershell
   Unblock-File .\jira-usage-report.ps1
   ```
2. Set your credentials (once per session - or add these same 5 lines to
   your PowerShell `$PROFILE` so you never repeat this again):
   ```powershell
   $env:JIRA_BASE = "https://your-domain.atlassian.net"
   $env:JIRA_USER = "you@company.com"
   $env:JIRA_TOKEN = "your-jira-api-token"
   $env:OPENOBSERVE_USER = "same login as step 1"
   $env:OPENOBSERVE_PASSWORD = "same password as step 1"
   ```

   **Optional alternative:** if you'd rather keep everything in one file
   instead of typing these five lines, add them to your `.env` from step
   1 (they're not there by default - only the Docker-specific settings
   are), then run:
   ```powershell
   .\Load-DotEnv.ps1 -Path ..\.env
   ```
   instead of the five lines above. Must be run directly, not via
   `powershell -File Load-DotEnv.ps1` - see its own header comment for
   why.
3. Run it:
   ```powershell
   .\jira-usage-report.ps1 -Ticket "PROJ-123"
   ```

That's it. Full details, every field explained, and troubleshooting all
live in `docs/` - start with `docs/jira-ticket-verification.md` if
something doesn't work as expected.
