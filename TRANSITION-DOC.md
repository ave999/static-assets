# SCCM Web GUI - Transition Document

## Repository
- **Repo**: `/home/user/static-assets`
- **Branch**: `claude/audit-powershell-script-UGIMl`
- **Remote**: `origin`

## Files

| File | Purpose |
|------|---------|
| `Deploy-SCCMApplication-WebGUI.ps1` | Consolidated web GUI + deployment logic (THE MAIN FILE) |
| `Deploy-SCCMApplication-Improved.ps1` | Standalone CLI deployment script (works fine, no changes needed) |
| `Deploy-SCCMApplication-Original.ps1` | Original script for reference/audit |
| `SCCM-Deployment-Script-Audit.md` | Audit report of the original script |

## The Problem

The web GUI runs an HTTP server on port 80 that provides a browser-based form for SCCM application deployments. When the user clicks "Deploy" or "WhatIf", the script needs to:

1. Import the ConfigurationManager PowerShell module
2. Connect to the SCCM site (`Set-Location "CM0:\"`)
3. Run SCCM cmdlets (New-CMApplication, Add-CMScriptDeploymentType, etc.)

**The SCCM connection works perfectly when run directly from PowerShell** (interactive session on the SCCM server). The user's working code is simply:

```powershell
Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1')
Set-Location "$($SiteCode):\"
```

**The SCCM connection FAILS when run from any background context** started by the web GUI:

| Approach Tried | Result |
|----------------|--------|
| `Start-Job` | RPC server unavailable (new process) |
| `Start-Process` | RPC server unavailable (new process) |
| `[PowerShell]::Create()` (default runspace) | RPC server unavailable (MTA threading) |
| `[PowerShell]::Create()` with STA runspace | Sometimes "Invalid namespace", sometimes "RPC server unavailable" |
| STA runspace + explicit `New-PSDrive` | RPC server unavailable |

## Root Cause Analysis

The ConfigurationManager module uses COM/DCOM and WMI to communicate with the SCCM site server. When the module is imported, it triggers WMI queries via `System.Management.ManagementScope.Initialize()`. These queries fail in any execution context that differs from an interactive PowerShell session.

The exact WMI call path from the error:
```
Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlQueryProcessor.ExecuteQuery()
  -> System.Management.ManagementObjectSearcher.Get()
    -> System.Management.ManagementScope.Initialize()
      -> FAILS with RPC or Invalid namespace
```

**Key facts:**
- Machine: `WAZEU2PRDDE051.corp.internal.citizensbank.com` (IS the SCCM site server)
- Site Code: `CM0`
- User: `ns06703`
- SMS_ADMIN_UI_PATH: `E:\Program Files\Microsoft Configuration Manager\AdminConsole\bin\i386`
- Module path: `E:\Program Files\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1`
- The `.Substring(0, Length-5)` removes `i386` (last 5 chars including the `\` before it), yielding the `bin\` directory

## Recommended Solution (Not Yet Implemented)

**Flip the architecture: run the HTTP server in a background runspace, run SCCM deployments on the main thread.**

The main thread IS the interactive PowerShell session — the exact context where SCCM works. The HTTP server doesn't need WMI access, so it's safe to run in a runspace.

### Architecture:

```
Main Thread (interactive PS session)     Background Runspace
─────────────────────────────────────    ────────────────────
                                         HTTP Server (port 80)
                                           ↕ reads/writes
Deployment Logic ←──────────────────→  SharedState (synchronized hashtable)
  Import-Module CM                        ↕ reads/writes
  Set-Location CM0:\                     Browser (HTML/JS)
  New-CMApplication, etc.
```

### Implementation:

```powershell
# Thread-safe shared state
$SharedState = [hashtable]::Synchronized(@{
    LogMessages  = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    IsDeploying  = $false
    DeployRequest = $null   # JSON string set by HTTP server when user clicks Deploy
    StopServer   = $false
})

# HTTP server runs in a runspace (doesn't need WMI)
$HttpServerBlock = {
    param($SharedState, $Port)
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$Port/")
    $listener.Start()
    while (-not $SharedState.StopServer) {
        $ar = $listener.BeginGetContext($null, $null)
        while (-not $ar.AsyncWaitHandle.WaitOne(500)) {
            if ($SharedState.StopServer) { break }
        }
        if ($SharedState.StopServer) { break }
        $context = $listener.EndGetContext($ar)
        # Handle: /, /api/logs, /api/deploy, /api/clear-log
        # For /api/deploy: $SharedState.DeployRequest = $requestBody
        # For /api/logs: return $SharedState.LogMessages + $SharedState.IsDeploying
    }
    $listener.Stop(); $listener.Close()
}

# Launch HTTP server
$httpRunspace = [runspacefactory]::CreateRunspace()
$httpRunspace.Open()
$httpPs = [PowerShell]::Create()
$httpPs.Runspace = $httpRunspace
$httpPs.AddScript($HttpServerBlock).AddArgument($SharedState).AddArgument(80) | Out-Null
$httpPs.BeginInvoke() | Out-Null

# Main loop: process deployments on the MAIN THREAD
while (-not $SharedState.StopServer) {
    if ($SharedState.DeployRequest) {
        $body = $SharedState.DeployRequest
        $SharedState.DeployRequest = $null
        $SharedState.IsDeploying = $true

        # THIS runs on the main thread = same context as interactive PowerShell
        Import-Module ($env:SMS_ADMIN_UI_PATH.Substring(0, $env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1')
        Set-Location "CM0:\"
        # ... run all SCCM deployment steps ...

        $SharedState.IsDeploying = $false
    }
    Start-Sleep -Milliseconds 200
}
```

### Key Implementation Details:

1. **Deployment logging**: Write-DeployLog function adds messages to `$SharedState.LogMessages` AND writes to console with `Write-Host`
2. **HTML/JS stays the same**: The Get-HTMLPage function and all client-side code is unchanged. Move it inside the HTTP server scriptblock.
3. **HTTP server handlers**:
   - `GET /` → Return HTML page
   - `GET /api/logs` → Return `$SharedState.LogMessages` as JSON array + `$SharedState.IsDeploying`
   - `POST /api/deploy` → Store request body in `$SharedState.DeployRequest`, return `{"success":true}`
   - `POST /api/clear-log` → Clear `$SharedState.LogMessages`
4. **Async HTTP listening**: Use `BeginGetContext` with 500ms timeout so the server can check `$SharedState.StopServer` periodically for graceful shutdown
5. **Ctrl+C handling**: Set `$SharedState.StopServer = $true` in a `finally` block

## Current State of Deploy-SCCMApplication-WebGUI.ps1

The current file has the consolidated architecture (deployment logic embedded as `$script:DeploymentScriptBlock`, runs in a runspace). It needs to be refactored to the "flipped" architecture described above.

### What works in the current file:
- HTML/CSS/JS (Citizens Bank branding, form validation, real-time log polling)
- Form fields and validation (required fields: AppName, ContentLocation, InstallCommand, LimitingCollection, DPGroupName)
- Site Code `CM0` and Site Server `WAZEU2PRDDE051.corp.internal.citizensbank.com` hardcoded
- All SCCM deployment steps (create app, detection rules, deployment type, OS requirements, content distribution, collections, deployments, folder organization)
- WhatIf mode (boolean flag, not ShouldProcess)
- Rollback on failure
- Real-time log streaming via PSDataCollection
- Auto-generated default names (DeploymentTypeName, InstallCollectionName, UninstallCollectionName based on AppName)

### What needs to change:
- Move HTTP server into a runspace scriptblock
- Move deployment logic into a main-thread function
- Replace `$script:` state variables with `$SharedState` synchronized hashtable
- Replace `Write-Output` in deployment scriptblock with function that writes to `$SharedState.LogMessages`

## User Preferences

- **Keep it simple** — user repeatedly asked to simplify and not over-engineer
- **Use their exact SCCM connection code** — `Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1')` then `Set-Location "$($SiteCode):\"` — nothing else
- **No hardcoded application defaults** — all app-specific values come from the form
- **PowerShell 5.1 compatibility** — no PS 7+ features
- **Citizens Bank branding** — `#00594c` deep green, `#008361` bright green
- **Module path**: The `.Substring(0, Length-5)` approach removes `\i386` from the end of `SMS_ADMIN_UI_PATH` to get `...\bin\`. Do NOT use `Split-Path`, do NOT add `i386` anywhere, do NOT navigate with `..`

## Hardcoded Values
- Port: `80`
- Site Code: `CM0`
- Site Server: `WAZEU2PRDDE051.corp.internal.citizensbank.com`
- Remote access: always enabled (bind to all interfaces with `http://+:80/`)
