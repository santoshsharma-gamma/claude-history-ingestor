
Follow below steps to run ./script/claude-report.ps1:

1. Check if you already have a profile file:
   #### `Test-Path $PROFILE`
    
    #### If it prints False, create it first:

	PS C:\claude-history-ingestor> `New-Item -ItemType File -Path $PROFILE -Force`
	
	    Above command creates Microsoft.PowerShell_profile.ps1 in directory: C:\Users\<profile_user>\OneDrive - Gamma Telecom Ltd\Documents\WindowsPowerShell
	
2. Open it in Notepad:
   C:\Users\<profile_user>\OneDrive - Gamma Telecom Ltd\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1

3. Add these five lines (replace the two token/password placeholders with your real value)
    $env:JIRA_BASE = "https://gammatelecom.atlassian.net"
    $env:JIRA_USER = "firstname.lastname@gamma.co.uk"
    $env:JIRA_TOKEN = "your-real-jira-token"  -- from: https://id.atlassian.com/manage-profile/security/api-tokens
    $env:OPENOBSERVE_USER = "open-observe.username@gamma.co.uk"
    $env:OPENOBSERVE_PASSWORD = "your-real-openobserve-password"
4. `Unblock-File -Path .\scripts\claude-report.ps1`
5. `.\script\claude-report.ps1 -Ticket "GGLOBDRA-1970"`