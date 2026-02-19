<#

.SYNOPSIS

Web-based GUI for SCCM Application Deployment

.DESCRIPTION

Launches a web server providing an HTML interface for deploying SCCM applications.

Accessible from network on port 80.

.NOTES

Author: Web GUI wrapper for Deploy-SCCMApplication-Improved.ps1

Version: 1.0

Requires: PowerShell 5.1+, Modern web browser

#>

[CmdletBinding()]

param()

$Port = 80 # Fixed port

$ErrorActionPreference = 'Stop'

# Get script directory

$ScriptPath = Split-Path -Parent $PSCommandPath

$DeploymentScript = Join-Path $ScriptPath "Deploy-SCCMApplication-Improved.ps1"

# Check if deployment script exists

if (-not (Test-Path $DeploymentScript)) {

Write-Error "Deploy-SCCMApplication-Improved.ps1 not found in the same folder!"

exit 1

}

# Global variables for state management

$script:LogMessages = @()

$script:IsDeploying = $false

$script:CurrentJobId = $null

$script:CurrentLogFile = $null

#region HTTP Server Functions

function Get-ContentType {

param([string]$Extension)

$contentTypes = @{

'.html' = 'text/html'

'.css' = 'text/css'

'.js' = 'application/javascript'

'.json' = 'application/json'

'.png' = 'image/png'

'.jpg' = 'image/jpeg'

'.ico' = 'image/x-icon'

}

$type = $contentTypes[$Extension]

if ($type) {

return $type

}

return 'text/plain'

}

function Send-HttpResponse {

param(

[System.Net.HttpListenerContext]$Context,

[string]$Content,

[string]$ContentType = 'text/html',

[int]$StatusCode = 200

)

$buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)

$Context.Response.ContentLength64 = $buffer.Length

$Context.Response.ContentType = "$ContentType; charset=utf-8"

$Context.Response.StatusCode = $StatusCode

$Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)

$Context.Response.OutputStream.Close()

}

function Get-HTMLPage {

return @'

<!DOCTYPE html>

<html lang="en">

<head>





<title>SCCM Application Deployment Tool</title>



</head>

<body>

<div class="container">

<div class="header">

<h1>SCCM Application Deployment Tool</h1>

<p>Automated deployment with real-time monitoring</p>

</div>

<div class="tabs">







</div>

<div id="config" class="tab-content active">

<h2>Application Configuration</h2>

<div id="validationSummary" class="validation-summary">

<h3>⚠️ Please fix the following errors:</h3>

<ul id="validationErrors"></ul>

</div>

<div class="form-row">

<div class="form-group">

<label class="required">Application Name</label>



<div class="error-message" id="appName-error">Application Name is required</div>

<div class="help-text">Unique name for the application in SCCM</div>

</div>

<div class="form-group">

<label>Deployment Type Name</label>



</div>

</div>

<div class="form-group">

<label>Description</label>



</div>

<fieldset class="fieldset">

<legend>📁 Content Settings</legend>

<div class="form-group">

<label class="required">Content Location (UNC Path)</label>



<div class="error-message" id="contentLocation-error">Content Location is required and must be a UNC path (\\server\share\folder)</div>

<div class="help-text">Network path to application source files (type the full UNC path manually)</div>

</div>

<div class="form-row">

<div class="form-group">

<label class="required">Install Command</label>



<div class="error-message" id="installCmd-error">Install Command is required</div>

</div>

<div class="form-group">

<label>Uninstall Command</label>



</div>

</div>

<div class="form-group">

<label>Maximum Runtime (minutes)</label>



</div>

</fieldset>

<fieldset class="fieldset">

<legend>📦 Collections & Distribution</legend>

<div class="form-group">

<label class="required">Limiting Collection</label>



<div class="error-message" id="limitingCollection-error">Limiting Collection is required</div>

</div>

<div class="form-row">

<div class="form-group">

<label>Install Collection</label>



</div>

<div class="form-group">

<label>Uninstall Collection</label>



</div>

</div>

<div class="form-group">

<label class="required">Distribution Point Group</label>



<div class="error-message" id="dpGroup-error">Distribution Point Group is required</div>

</div>

</fieldset>

<fieldset class="fieldset">

<legend>📂 Console Organization</legend>

<div class="form-row">

<div class="form-group">

<label>Application Folder Path</label>



</div>

<div class="form-group">

<label>Collection Folder Path</label>



</div>

</div>

</fieldset>

</div>

<div id="options" class="tab-content">

<h2>Deployment Options</h2>

<div class="form-group checkbox-group">



<label for="enableLogging">Enable file logging</label>

</div>

<div class="form-group">

<label>Log File Path</label>



<div class="help-text">Full path to log file (e.g., C:\Logs\deployment.log). Leave empty to skip file logging.</div>

</div>

<div class="form-group checkbox-group">



<label for="forceMode">Force mode (skip confirmation prompts)</label>

</div>

<div class="form-group checkbox-group">



<label for="noRollback">Disable automatic rollback on failure</label>

</div>

<div class="form-group checkbox-group">



<label for="verboseLogging">Enable verbose logging (recommended during testing)</label>

</div>

<div class="form-group">

<label>Collection Creation Timeout (minutes)</label>



</div>

</div>

<div id="log" class="tab-content">

<h2>Execution Log <span id="statusBadge" class="status-badge status-ready">Ready</span></h2>

<div class="log-controls">







</div>

<div id="logContainer" class="log-container">Ready to deploy. Configure your settings and click "Deploy" or "WhatIf" to begin.</div>

</div>

<div class="actions">





</div>

</div>



</body>

</html>

'@

}

#endregion

#region API Handlers

function Handle-GetLogs {

param([System.Net.HttpListenerContext]$Context)

# Read logs from file if deployment is running

if ($script:CurrentJobId -and $script:CurrentLogFile) {

try {

$process = Get-Process -Id $script:CurrentJobId -ErrorAction SilentlyContinue

if (Test-Path $script:CurrentLogFile) {

# Read log file content

$content = Get-Content $script:CurrentLogFile -Raw -ErrorAction SilentlyContinue

if ($content) {

$script:LogMessages = $content -split "`n"

}

}

# Check if process is still running

if (-not $process) {

$script:LogMessages += ""

$script:LogMessages += "========================================="

$script:LogMessages += "DEPLOYMENT PROCESS COMPLETED"

$script:LogMessages += "========================================="

$script:IsDeploying = $false

$script:CurrentJobId = $null

}

}

catch {

$script:LogMessages += "Error reading log: $_"

}

}

$response = @{

logs = $script:LogMessages

isDeploying = $script:IsDeploying

} | ConvertTo-Json

Send-HttpResponse -Context $Context -Content $response -ContentType 'application/json'

}

function Handle-ClearLog {

param([System.Net.HttpListenerContext]$Context)

$script:LogMessages = @()

$script:LogMessages += "Log cleared at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Send-HttpResponse -Context $Context -Content '{"success":true}' -ContentType 'application/json'

}

function Handle-Deploy {

param([System.Net.HttpListenerContext]$Context)

if ($script:IsDeploying) {

Send-HttpResponse -Context $Context -Content '{"success":false,"error":"Deployment already in progress"}' -ContentType 'application/json'

return

}

# Read request body

$reader = New-Object System.IO.StreamReader($Context.Request.InputStream)

$body = $reader.ReadToEnd()

$config = $body | ConvertFrom-Json

# Clear logs

$script:LogMessages = @()

$script:IsDeploying = $true

# Log the incoming request

$script:LogMessages += "=== WEB GUI REQUEST ==="

$script:LogMessages += "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$script:LogMessages += "Mode: $(if ($config.WhatIf) { 'WhatIf' } else { 'Deploy' })"

$script:LogMessages += "Application: $($config.AppName)"

$script:LogMessages += "Site: $($config.SiteCode) @ $($config.SiteServerFqdn)"

$script:LogMessages += "Content: $($config.ContentLocation)"

$script:LogMessages += "Install Cmd: $($config.InstallCommand)"

$script:LogMessages += "Uninstall Cmd: $(if ($config.UninstallCommand) { $config.UninstallCommand } else { '(not provided)' })"

$script:LogMessages += "========================"

$script:LogMessages += ""

# Build parameters

$params = @{

AppName = $config.AppName

Description = $config.Description

SiteCode = $config.SiteCode

SiteServerFqdn = $config.SiteServerFqdn

ContentLocation = $config.ContentLocation

InstallCommand = $config.InstallCommand

UninstallCommand = $config.UninstallCommand

DeploymentTypeName = $config.DeploymentTypeName

DPGroupName = $config.DPGroupName

LimitingCollectionName = $config.LimitingCollectionName

ApplicationFolder = $config.ApplicationFolder

CollectionFolder = $config.CollectionFolder

MaxRuntimeMins = $config.MaxRuntimeMins

CollectionCreationTimeoutMinutes = $config.CollectionCreationTimeoutMinutes

Confirm = $false

}

if ($config.InstallCollectionName) { $params.InstallCollectionName = $config.InstallCollectionName }

if ($config.UninstallCollectionName) { $params.UninstallCollectionName = $config.UninstallCollectionName }

if ($config.LogFilePath -and $config.LogFilePath.Trim()) { $params.LogFilePath = $config.LogFilePath.Trim() }

if ($config.Force) { $params.Force = $true }

if ($config.NoRollback) { $params.NoRollback = $true }

if ($config.VerboseLogging) { $params.VerboseLogging = $true }

if ($config.WhatIf) { $params.WhatIf = $true }

# Create temporary log file for output

$script:CurrentLogFile = Join-Path $env:TEMP "sccm-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Build PowerShell command

$paramString = ($params.GetEnumerator() | ForEach-Object {

if ($_.Value -is [bool]) {

if ($_.Value) { "-$($_.Key)" }

} elseif ($_.Value -ne $null) {

"-$($_.Key) '$($_.Value -replace "'","''")'"

}

}) -join ' '

$psCommand = "& '$DeploymentScript' $paramString *>&1 | Tee-Object -FilePath '$script:CurrentLogFile'"

# Start deployment in new PowerShell process

$psi = New-Object System.Diagnostics.ProcessStartInfo

$psi.FileName = "powershell.exe"

$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$psCommand`""

$psi.UseShellExecute = $false

$psi.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::Start($psi)

$script:CurrentJobId = $process.Id

# Add initial log message

$script:LogMessages += "Starting deployment process (ID: $($process.Id))..."

$script:LogMessages += "Log file: $script:CurrentLogFile"

$script:LogMessages += "Waiting for output..."

Send-HttpResponse -Context $Context -Content '{"success":true}' -ContentType 'application/json'

}

#endregion

# Start HTTP listener

$listener = New-Object System.Net.HttpListener

# Bind to all network interfaces

$listener.Prefixes.Add("http://+:$Port/")

# Get local IP addresses

$localIPs = Get-NetIPAddress -AddressFamily IPv4 |

Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |

Select-Object -ExpandProperty IPAddress

$primaryIP = $localIPs | Select-Object -First 1

try {

$listener.Start()

Write-Host "========================================" -ForegroundColor Cyan

Write-Host "SCCM Deployment Web GUI Started" -ForegroundColor Green

Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""

Write-Host "Server is accessible from network:" -ForegroundColor Yellow

Write-Host " Local: http://localhost:$Port" -ForegroundColor White

if ($primaryIP) {

Write-Host " Network: http://${primaryIP}:$Port" -ForegroundColor White

}

foreach ($ip in $localIPs) {

if ($ip -ne $primaryIP) {

Write-Host " http://${ip}:$Port" -ForegroundColor Gray

}

}

Write-Host ""

Write-Host "IMPORTANT: Ensure Windows Firewall allows port $Port" -ForegroundColor Yellow

Write-Host "Run this command as Administrator to open the port:" -ForegroundColor Gray

Write-Host " New-NetFirewallRule -DisplayName 'SCCM Web GUI' -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow" -ForegroundColor Cyan

Write-Host ""

Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""

# Try to open browser (only on localhost)

Start-Process "http://localhost:$Port"

while ($listener.IsListening) {

$context = $listener.GetContext()

$request = $context.Request

$response = $context.Response

try {

$path = $request.Url.LocalPath

switch -Regex ($path) {

'^/$' {

$html = Get-HTMLPage

Send-HttpResponse -Context $context -Content $html -ContentType 'text/html'

}

'^/api/logs$' {

Handle-GetLogs -Context $context

}

'^/api/clear-log$' {

Handle-ClearLog -Context $context

}

'^/api/deploy$' {

Handle-Deploy -Context $context

}

default {

Send-HttpResponse -Context $context -Content '404 Not Found' -StatusCode 404

}

}

}

catch {

Write-Host "Error handling request: $_" -ForegroundColor Red

Send-HttpResponse -Context $context -Content "Error: $_" -StatusCode 500

}

}

}

catch {

Write-Host "Error starting server: $_" -ForegroundColor Red

exit 1

}

finally {

if ($listener.IsListening) {

$listener.Stop()

}

$listener.Close()

# Clean up any running processes

if ($script:CurrentJobId) {

try {

Stop-Process -Id $script:CurrentJobId -Force -ErrorAction SilentlyContinue

}

catch {

# Process may have already exited

}

}

Write-Host "`nServer stopped." -ForegroundColor Yellow

}
