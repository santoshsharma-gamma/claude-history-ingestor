# Quickstart

## 0. One-time setup - all 6 values, asked once

From the folder containing `docker-compose.yml`:

```powershell
.\setEnvironment.ps1
```

Asks for the 6 values this whole project needs (Claude history path,
OpenObserve login, JIRA login) exactly once each, then writes them to
**both** places that need them - the `.env` file (for Docker) and your
PowerShell `$PROFILE` (for the JIRA report script). Safe to re-run any
time - e.g. rotating your JIRA token - it replaces its own clearly
marked block rather than duplicating lines on every run.

**Close and reopen your terminal after running this once** - profile
changes only take effect in a fresh PowerShell session.

## 1. Start the Docker ingestor (reads your own Claude Code history)

```powershell
docker compose up -d
```

Open http://localhost:5080, log in with the OpenObserve credentials
from step 0. Give it ~15 seconds, then check **Streams →
`claude_code_history`** has data.

## 2. Run the JIRA usage report (PowerShell)

From the `scripts/` folder:

1. One-time only - unblock the script so Windows stops warning about it:
   ```powershell
   Unblock-File .\claude-report.ps1
   ```
2. Run it - no credentials to type, step 0 already set them:
   ```powershell
   .\claude-report.ps1 -Ticket "PROJ-123"
   ```

That's it. Full details, every field explained, and troubleshooting all
live in `docs/` - start with `docs/jira-ticket-verification.md` if
something doesn't work as expected.