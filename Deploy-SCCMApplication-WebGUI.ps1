[CmdletBinding()]
param()

$Port = 80
$SiteCode = 'CM0'
$SiteServer = 'WAZEU2PRDDE051.corp.internal.citizensbank.com'
$ErrorActionPreference = 'Stop'

#region Shared State

# Thread-safe state shared between the HTTP server runspace and the main thread.
$SharedState = [hashtable]::Synchronized(@{
LogMessages = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
IsDeploying = $false
DeployRequest = $null # JSON string written by HTTP server; read & cleared by main thread
StopServer = $false
})

#endregion

#region HTTP Server Scriptblock (runs in background runspace — no WMI needed)

$HttpServerBlock = {
param($SharedState, $Port)

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
<h3>Please fix the following errors:</h3>
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
<legend>Content Settings</legend>

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
<legend>Collections & Distribution</legend>

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
<legend>Console Organization</legend>

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

# Start the listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()

while (-not $SharedState.StopServer) {
try {
$ar = $listener.BeginGetContext($null, $null)

# Poll every 500 ms so we can check StopServer
while (-not $ar.AsyncWaitHandle.WaitOne(500)) {
if ($SharedState.StopServer) { break }
}

if ($SharedState.StopServer) { break }

$context = $listener.EndGetContext($ar)
$path = $context.Request.Url.LocalPath

try {
switch -Regex ($path) {

'^/$' {
Send-HttpResponse -Context $context -Content (Get-HTMLPage) -ContentType 'text/html'
}

'^/api/logs$' {
$json = @{
logs = @($SharedState.LogMessages)
isDeploying = [bool]$SharedState.IsDeploying
} | ConvertTo-Json
Send-HttpResponse -Context $context -Content $json -ContentType 'application/json'
}

'^/api/deploy$' {
if ($SharedState.IsDeploying -or $SharedState.DeployRequest) {
Send-HttpResponse -Context $context `
-Content '{"success":false,"error":"Deployment already in progress"}' `
-ContentType 'application/json'
} else {
$reader = New-Object System.IO.StreamReader($context.Request.InputStream)
$SharedState.DeployRequest = $reader.ReadToEnd()
Send-HttpResponse -Context $context -Content '{"success":true}' -ContentType 'application/json'
}
}

'^/api/clear-log$' {
$SharedState.LogMessages.Clear()
[void]$SharedState.LogMessages.Add("Log cleared at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
Send-HttpResponse -Context $context -Content '{"success":true}' -ContentType 'application/json'
}

'^/api/reset$' {
# Clears a stuck IsDeploying flag — use when the script crashed
# or was killed mid-deployment and the UI is frozen on "Deploying..."
$SharedState.IsDeploying = $false
$SharedState.DeployRequest = $null
[void]$SharedState.LogMessages.Add("")
[void]$SharedState.LogMessages.Add("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [WARN] Deployment state was manually reset. Verify SCCM console for any partial changes.")
Send-HttpResponse -Context $context -Content '{"success":true}' -ContentType 'application/json'
}

default {
Send-HttpResponse -Context $context -Content '404 Not Found' -StatusCode 404
}
}
} catch {
try {
Send-HttpResponse -Context $context -Content "Error: $_" -StatusCode 500
} catch {}
}

} catch [System.Net.HttpListenerException] {
# Listener was stopped externally
break
} catch {
# Ignore transient errors; keep the server running
}
}

try { $listener.Stop() } catch {}
try { $listener.Close() } catch {}
}

#endregion

#region Deployment Logic (runs on the main thread — same context as interactive PS session)

function Write-DeployLog {
param(
[string]$Message = "",
[ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step')]
[string]$Level = 'Info'
)

if ([string]::IsNullOrWhiteSpace($Message)) {
[void]$script:SharedState.LogMessages.Add("")
Write-Host ""
return
}

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$prefix = switch ($Level) {
'Step' { '[STEP]' }
'Success' { '[ OK ]' }
'Warning' { '[WARN]' }
'Error' { '[FAIL]' }
default { '[INFO]' }
}
$line = "[$timestamp] $prefix $Message"
[void]$script:SharedState.LogMessages.Add($line)
Write-Host $line
}

function Invoke-SCCMDeployment {
param([hashtable]$Config)

# Extract parameters
$AppName = $Config.AppName
$Description = if ($Config.Description) { $Config.Description } else { "" }
$SiteCode = $Config.SiteCode
$SiteServerFqdn = $Config.SiteServerFqdn
$ContentLocation = $Config.ContentLocation
$InstallCommand = $Config.InstallCommand
$UninstallCommand = if ($Config.UninstallCommand) { $Config.UninstallCommand } else { "" }
$DeploymentTypeName = $Config.DeploymentTypeName
$DPGroupName = $Config.DPGroupName
$LimitingCollectionName = $Config.LimitingCollectionName
$InstallCollectionName = $Config.InstallCollectionName
$UninstallCollectionName = $Config.UninstallCollectionName
$ApplicationFolder = if ($Config.ApplicationFolder) { $Config.ApplicationFolder } else { "" }
$CollectionFolder = if ($Config.CollectionFolder) { $Config.CollectionFolder } else { "" }
$MaxRuntimeMins = if ($Config.MaxRuntimeMins) { $Config.MaxRuntimeMins } else { 60 }
$CollectionCreationTimeoutMinutes = if ($Config.CollectionCreationTimeoutMinutes) { $Config.CollectionCreationTimeoutMinutes } else { 5 }
$LogFilePath = $Config.LogFilePath
$Force = [bool]$Config.Force
$NoRollback = [bool]$Config.NoRollback
$VerboseLogging = [bool]$Config.VerboseLogging
$WhatIf = [bool]$Config.WhatIf

$ErrorActionPreference = 'Stop'

# Auto-generate names based on AppName if not provided
if ([string]::IsNullOrWhiteSpace($DeploymentTypeName)) { $DeploymentTypeName = "${AppName}_Install" }
if ([string]::IsNullOrWhiteSpace($InstallCollectionName)) { $InstallCollectionName = $AppName }
if ([string]::IsNullOrWhiteSpace($UninstallCollectionName)){ $UninstallCollectionName = "${AppName}_Uninstall" }

# Track created objects for rollback
$createdObjects = @{
Application = $null
Collections = @()
Deployments = @()
}

# Local Write-Log: calls Write-DeployLog and optionally writes to a log file
function Write-Log {
param(
[string]$Message = "",
[ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step')]
[string]$Level = 'Info'
)
Write-DeployLog -Message $Message -Level $Level
if ($LogFilePath -and -not [string]::IsNullOrWhiteSpace($Message)) {
try {
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"[$ts] [$Level] $Message" | Out-File -FilePath $LogFilePath -Append -ErrorAction SilentlyContinue
} catch {}
}
}

function Invoke-Step {
param(
[string]$Name,
[scriptblock]$Script,
[switch]$ContinueOnError
)
Write-Log -Message $Name -Level 'Step'
try {
if ($VerboseLogging) {
$verboseOutput = & $Script 4>&1 3>&1 2>&1
foreach ($line in $verboseOutput) {
if ($line) { Write-Log -Message " [VERBOSE] $line" -Level 'Info' }
}
} else {
$null = & $Script
}
Write-Log -Message "$Name completed." -Level 'Success'
} catch {
Write-Log -Message "$Name failed." -Level 'Error'
Write-Log -Message "Error: $_" -Level 'Error'
if ($_.Exception.InnerException) {
Write-Log -Message "InnerException: $($_.Exception.InnerException)" -Level 'Error'
}
if (-not $ContinueOnError) { throw }
}
}

function Invoke-Rollback {
if ($NoRollback) {
Write-Log "Rollback disabled by parameter. Manual cleanup required." -Level 'Warning'
return
}

Write-Log "Initiating rollback of created objects..." -Level 'Warning'

foreach ($deployment in $createdObjects.Deployments) {
try {
Write-Log "Removing deployment: $deployment" -Level 'Info'
Remove-CMApplicationDeployment -DeploymentId $deployment -Force -ErrorAction Stop
} catch {
Write-Log "Failed to remove deployment ${deployment}: $_" -Level 'Error'
}
}

foreach ($collection in $createdObjects.Collections) {
try {
Write-Log "Removing collection: $collection" -Level 'Info'
Remove-CMDeviceCollection -Name $collection -Force -ErrorAction Stop
} catch {
Write-Log "Failed to remove collection ${collection}: $_" -Level 'Error'
}
}

if ($createdObjects.Application) {
try {
Write-Log "Removing application: $($createdObjects.Application)" -Level 'Info'
Remove-CMApplication -Name $createdObjects.Application -Force -ErrorAction Stop
} catch {
Write-Log "Failed to remove application: $_" -Level 'Error'
}
}

Write-Log "Rollback completed. Verify SCCM console for any remaining objects." -Level 'Warning'
}

#--- Main Deployment ---
try {
$originalLocation = Get-Location

Write-Log "========================================"
Write-Log "SCCM Application Deployment Script"
Write-Log "Application: $AppName"
Write-Log "Site: $SiteCode ($SiteServerFqdn)"
Write-Log "========================================"

if ($WhatIf) {
Write-Log "Running in WhatIf mode - no changes will be made" -Level 'Warning'
}

if ($VerboseLogging -or $WhatIf) {
Write-Log ""
Write-Log "=== PARAMETER VALUES ==="
Write-Log "AppName: $AppName"
Write-Log "Description: $Description"
Write-Log "SiteCode: $SiteCode"
Write-Log "SiteServerFqdn: $SiteServerFqdn"
Write-Log "ContentLocation: $ContentLocation"
Write-Log "InstallCommand: $InstallCommand"
Write-Log "UninstallCommand: $UninstallCommand"
Write-Log "DeploymentTypeName: $DeploymentTypeName"
Write-Log "DPGroupName: $DPGroupName"
Write-Log "LimitingCollectionName: $LimitingCollectionName"
Write-Log "InstallCollectionName: $InstallCollectionName"
Write-Log "UninstallCollectionName: $UninstallCollectionName"
Write-Log "ApplicationFolder: $ApplicationFolder"
Write-Log "CollectionFolder: $CollectionFolder"
Write-Log "MaxRuntimeMins: $MaxRuntimeMins"
Write-Log "LogFilePath: $LogFilePath"
Write-Log "Force: $Force"
Write-Log "NoRollback: $NoRollback"
Write-Log "WhatIf: $WhatIf"
Write-Log "VerboseLogging: $VerboseLogging"
Write-Log "======================="
Write-Log ""
}

#--- Pre-flight Validation ---
Invoke-Step -Name "Pre-flight validation" -Script {
Write-Log "Current User: $env:USERNAME"
Write-Log "Current Computer: $env:COMPUTERNAME"

Write-Log "SMS_ADMIN_UI_PATH: $env:SMS_ADMIN_UI_PATH"
Write-Log "ConfigMgr module loaded (imported at startup)"

Write-Log "Checking content location: $ContentLocation"
if (-not (Test-Path $ContentLocation -PathType Container)) {
throw "Content location not accessible: $ContentLocation"
}
Write-Log "Content location accessible"

if ($InstallCommand -match '%.*%') {
Write-Log "Install command contains environment variable(s) - skipping file validation"
} else {
$installFile = Join-Path $ContentLocation $InstallCommand
if (-not (Test-Path $installFile)) {
throw "Installation command file not found: $installFile"
}
Write-Log "Install file found"
}

if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
if ($UninstallCommand -match '%.*%') {
Write-Log "Uninstall command contains environment variable(s) - skipping file validation"
} else {
$uninstallFile = Join-Path $ContentLocation $UninstallCommand
if (-not (Test-Path $uninstallFile)) {
Write-Log "Uninstall command file not found: $uninstallFile (continuing)" -Level 'Warning'
}
}
}
}

#--- Connect to SCCM site ---
# Import-Module registers the CMSite PS provider but does not always auto-create
# the PSDrive (it normally would, but only if WMI site enumeration succeeds during
# import). Explicitly creating the drive if it doesn't exist is reliable in all cases.
Invoke-Step -Name "Connect to SCCM site $SiteCode" -Script {
if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
Write-Log "CMSite drive not found — creating CM0: -> $SiteServerFqdn"
New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServerFqdn -ErrorAction Stop | Out-Null
}
Set-Location "$($SiteCode):\" -ErrorAction Stop
}

#--- Deployment Steps ---
try {

# Remove existing application if present
Invoke-Step -Name "Check and remove existing application '$AppName'" -Script {
$existingDeployments = Get-CMApplicationDeployment -Name $AppName -ErrorAction SilentlyContinue
if ($existingDeployments) {
Write-Log "Found $($existingDeployments.Count) existing deployment(s)"
if (-not $WhatIf) {
foreach ($deployment in $existingDeployments) {
Remove-CMApplicationDeployment -InputObject $deployment -Force -ErrorAction Stop
Write-Log "Removed deployment to: $($deployment.CollectionName)" -Level 'Success'
}
} else {
Write-Log "[WHATIF] Would remove $($existingDeployments.Count) existing deployment(s)"
}
}

$existing = Get-CMApplication -Name $AppName -Fast -ErrorAction SilentlyContinue
if ($existing) {
Write-Log "Found existing application '$AppName'"
if (-not $WhatIf) {
Remove-CMApplication -Name $AppName -Force -ErrorAction Stop
Write-Log "Removed existing application" -Level 'Success'
} else {
Write-Log "[WHATIF] Would remove existing application '$AppName'"
}
}
}

# Create application
Invoke-Step -Name "Create application '$AppName'" -Script {
if (-not $WhatIf) {
New-CMApplication -Name $AppName -Description $Description -ErrorAction Stop | Out-Null
$createdObjects.Application = $AppName
} else {
Write-Log "[WHATIF] Would create application '$AppName'"
}
}

# Build detection clauses
Write-Log "Building detection rules" -Level 'Step'

# $clause1 = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName "Software\Microsoft\Office\ClickToRun\Configuration" -ValueName "VersionToReport" -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue "16.0.11929.20562" -value
$clause1 = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -I64Bit -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\!$($AppName)" -Existence -PropertyType String -ValueName $($dtParams.ValueName)

# $clause2 = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ProPlus2024Volume - en-us" -ValueName "DisplayName" -PropertyType String -ExpressionOperator IsEquals -ExpectedValue "Microsoft Office LTSC Professional Plus 2024 - en-us" -value
$clause2 = New-CMDetectionClauseRegistryKeyValue -Hive LocalMachine -Is64Bit -KeyName "SOFTWARE\WOW6432\Microsoft\Windows\CurrentVersion\Uninstall\!$($AppName)" -Existence -PropertyType String -ValueName "UninstallString"

$clause3 = New-CMDetectionClauseFile -Path "C:\Program Files\Application" -FileName App.exe -Value -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue "1.0.0"

$clause4 = New-CMDetectionClauseDirectory -DirectoryName "Windows" -Path "%systemdrive%" -Existence


Write-Log "Detection clauses created successfully" -Level 'Success'

# Add deployment type with detection
Invoke-Step -Name "Add Script/EXE deployment type" -Script {
if (-not $WhatIf) {
$dtParams = @{
ApplicationName = $AppName
DeploymentTypeName = $DeploymentTypeName
ContentLocation = $ContentLocation
InstallCommand = $InstallCommand
UninstallCommand = $UninstallCommand
InstallationBehaviorType = 'InstallForSystem'
LogonRequirementType = 'WhetherOrNotUserLoggedOn'
UserInteractionMode = 'Hidden'
MaximumRuntimeMins = $MaxRuntimeMins
RebootBehavior = 'BasedOnExitCode'
SlowNetworkDeploymentMode = 'Download'
ValueName = "UninstallString"

}

Add-CMScriptDeploymentType @dtParams `
-ContentFallback `
-EnableBranchCache `
-AddDetectionClause $clause1, $clause2, $clause3, $clause4 `
-ErrorAction Stop | Out-Null

Write-Log "Deployment type created with 2 detection rules (AND logic)" -Level 'Success'
} else {
Write-Log "[WHATIF] Would add deployment type '$DeploymentTypeName' with detection rules"
}
}

# Set OS requirements
Invoke-Step -Name "Add OS requirement (Windows 11 x64/ARM64)" -Script {
if (-not $WhatIf) {
$osGC = Get-CMGlobalCondition -Name "Operating System" |
Where-Object PlatformType -eq 1

if (-not $osGC) {
throw "Operating System global condition not found"
}

Set-CMDeploymentType -ApplicationName $AppName `
-DeploymentTypeName $DeploymentTypeName `
-ClearRequirements -ErrorAction Stop | Out-Null

$osRule = $osGC | New-CMRequirementRuleOperatingSystemValue `
-PlatformString @(
'Windows/All_x64_Windows_11_and_higher_Clients',
'Windows/All_ARM64_Windows_11_and_higher_Clients'
) `
-RuleOperator OneOf

Set-CMScriptDeploymentType -ApplicationName $AppName `
-DeploymentTypeName $DeploymentTypeName `
-AddRequirement $osRule -ErrorAction Stop | Out-Null

Write-Log "OS requirements configured: Windows 11 (x64 + ARM64)" -Level 'Success'
} else {
Write-Log "[WHATIF] Would set OS requirement to Windows 11 x64/ARM64"
}
}

# Distribute content to DP group
Invoke-Step -Name "Distribute content to DP group '$DPGroupName'" -Script {
$dpGroupObj = Get-CMDistributionPointGroup -Name $DPGroupName -ErrorAction SilentlyContinue
if (-not $dpGroupObj) {
throw "Distribution Point Group '$DPGroupName' not found."
}

if (-not $WhatIf) {
Start-CMContentDistribution -ApplicationName $AppName `
-DistributionPointGroupName $DPGroupName -ErrorAction Stop | Out-Null
Write-Log "Content distribution initiated to $($dpGroupObj.MemberCount) distribution point(s)" -Level 'Success'
} else {
Write-Log "[WHATIF] Would distribute content to '$DPGroupName'"
}
}

# Create install collection
Invoke-Step -Name "Create device collection '$InstallCollectionName'" -Script {
$limiter = Get-CMDeviceCollection -Name $LimitingCollectionName -ErrorAction SilentlyContinue
if (-not $limiter) {
throw "Limiting collection '$LimitingCollectionName' not found."
}

$existing = Get-CMDeviceCollection -Name $InstallCollectionName -ErrorAction SilentlyContinue
if (-not $existing) {
if (-not $WhatIf) {
New-CMDeviceCollection -Name $InstallCollectionName `
-LimitingCollectionId $limiter.CollectionID `
-ErrorAction Stop | Out-Null

Write-Log "Collection created, waiting for provider replication..."
$timeout = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
$retryCount = 0
do {
Start-Sleep -Seconds 3
$retryCount++
$existing = Get-CMDeviceCollection -Name $InstallCollectionName -ErrorAction SilentlyContinue
if ($existing) {
Write-Log "Collection verified after $retryCount attempt(s)" -Level 'Success'
break
}
if ([datetime]::UtcNow -gt $timeout) {
throw "Collection creation timed out after $CollectionCreationTimeoutMinutes minutes."
}
} while (-not $existing)

$createdObjects.Collections += $InstallCollectionName
} else {
Write-Log "[WHATIF] Would create device collection '$InstallCollectionName'"
}
} else {
Write-Log "Collection '$InstallCollectionName' already exists"
}
}

# Create uninstall collection
Invoke-Step -Name "Create device collection '$UninstallCollectionName'" -Script {
$limiter = Get-CMDeviceCollection -Name $LimitingCollectionName -ErrorAction SilentlyContinue
if (-not $limiter) {
throw "Limiting collection '$LimitingCollectionName' not found."
}

$existing = Get-CMDeviceCollection -Name $UninstallCollectionName -ErrorAction SilentlyContinue
if (-not $existing) {
if (-not $WhatIf) {
New-CMDeviceCollection -Name $UninstallCollectionName `
-LimitingCollectionId $limiter.CollectionID `
-ErrorAction Stop | Out-Null

Write-Log "Collection created, waiting for provider replication..."
$timeout = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
$retryCount = 0
do {
Start-Sleep -Seconds 3
$retryCount++
$existing = Get-CMDeviceCollection -Name $UninstallCollectionName -ErrorAction SilentlyContinue
if ($existing) {
Write-Log "Collection verified after $retryCount attempt(s)" -Level 'Success'
break
}
if ([datetime]::UtcNow -gt $timeout) {
throw "Collection creation timed out after $CollectionCreationTimeoutMinutes minutes."
}
} while (-not $existing)

$createdObjects.Collections += $UninstallCollectionName
} else {
Write-Log "[WHATIF] Would create device collection '$UninstallCollectionName'"
}
} else {
Write-Log "Collection '$UninstallCollectionName' already exists"
}
}

# Create install deployment
Invoke-Step -Name "Deploy '$AppName' to '$InstallCollectionName' (Install / Required)" -Script {
$retries = 0
$maxRetries = 10
$collection = $null

do {
$collection = Get-CMDeviceCollection -Name $InstallCollectionName -ErrorAction SilentlyContinue
if ($collection) { break }
if ($retries -gt 0) {
Write-Log "Waiting for collection replication... (attempt $retries/$maxRetries)"
Start-Sleep -Seconds 5
}
$retries++
} while ($retries -le $maxRetries)

if (-not $collection -and -not $WhatIf) {
throw "Collection '$InstallCollectionName' not found after $maxRetries retries."
}

if (-not $WhatIf) {
$deployment = New-CMApplicationDeployment `
-ApplicationName $AppName `
-CollectionId $collection.CollectionID `
-DeployAction Install `
-DeployPurpose Required `
-UserNotification DisplaySoftwareCenterOnly `
-ErrorAction Stop

$createdObjects.Deployments += $deployment.DeploymentID
Write-Log "Deployment created (ID: $($deployment.DeploymentID))" -Level 'Success'
} else {
Write-Log "[WHATIF] Would create Install/Required deployment to '$InstallCollectionName'"
}
}

# Move application to folder (if specified)
if (-not [string]::IsNullOrWhiteSpace($ApplicationFolder)) {
Invoke-Step -Name "Move application to folder '$ApplicationFolder'" -Script {
$fullPath = "${SiteCode}:\Application\${ApplicationFolder}"
if (-not $WhatIf) {
$app = Get-CMApplication -Name $AppName -ErrorAction Stop
Move-CMObject -FolderPath $fullPath -InputObject $app -ErrorAction Stop
} else {
Write-Log "[WHATIF] Would move application to '$fullPath'"
}
}
}

# Move collections to folder (if specified)
if (-not [string]::IsNullOrWhiteSpace($CollectionFolder)) {
Invoke-Step -Name "Move collections to folder '$CollectionFolder'" -Script {
$fullPath = "${SiteCode}:\DeviceCollection\${CollectionFolder}"
foreach ($collName in @($InstallCollectionName, $UninstallCollectionName)) {
if (-not $WhatIf) {
$coll = Get-CMDeviceCollection -Name $collName -ErrorAction Stop
Move-CMObject -FolderPath $fullPath -InputObject $coll -ErrorAction Stop
Write-Log "Moved collection: $collName"
} else {
Write-Log "[WHATIF] Would move collection '$collName' to '$fullPath'"
}
}
}
}

Write-Log ""
Write-Log "========================================" -Level 'Success'
Write-Log "ALL STEPS COMPLETED SUCCESSFULLY" -Level 'Success'
Write-Log "Application: $AppName" -Level 'Success'
Write-Log "========================================" -Level 'Success'

} catch {
Write-Log "Deployment failed: $_" -Level 'Error'
if (-not $NoRollback -and $createdObjects.Application) {
Invoke-Rollback
}
throw
}

} catch {
Write-Log "Script execution failed: $_" -Level 'Error'
} finally {
# Return to filesystem location
try {
if ((Get-Location).Provider.Name -eq 'CMSite' -and $originalLocation) {
Set-Location $originalLocation.Path -ErrorAction SilentlyContinue
}
} catch {}

if ($LogFilePath) {
Write-Log "Log file saved to: $LogFilePath"
}
}
}

#endregion

#region Import ConfigurationManager Module (must happen before ANY runspace is created)
#
# The CM module initialises its SMS WMI provider via System.Management.ManagementScope.
# That initialisation succeeds only while the process is in a pure STA context — i.e.
# before we launch the HTTP runspace thread (which is MTA by default).
# Importing here, on the main thread, before any background thread exists, is the
# only reliable way to get WMI to initialise cleanly.

Write-Host "Importing ConfigurationManager module..." -ForegroundColor Cyan

if (-not $env:SMS_ADMIN_UI_PATH) {
Write-Host "ERROR: SMS_ADMIN_UI_PATH is not set. Is the ConfigMgr console installed?" -ForegroundColor Red
exit 1
}

$cmModulePath = $env:SMS_ADMIN_UI_PATH.Substring(0, $env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1'

if (-not (Test-Path $cmModulePath)) {
Write-Host "ERROR: ConfigurationManager module not found at: $cmModulePath" -ForegroundColor Red
exit 1
}

Import-Module $cmModulePath -ErrorAction Stop

Write-Host "ConfigurationManager module imported." -ForegroundColor Green
Write-Host ""

#endregion

#region Launch HTTP Server in Background Runspace

$httpRunspace = [runspacefactory]::CreateRunspace()
$httpRunspace.Open()
$httpPs = [PowerShell]::Create()
$httpPs.Runspace = $httpRunspace
$httpPs.AddScript($HttpServerBlock).AddArgument($SharedState).AddArgument($Port) | Out-Null
$httpHandle = $httpPs.BeginInvoke()

#endregion

#region Startup Banner

$localIPs = @()
try {
$localIPs = Get-NetIPAddress -AddressFamily IPv4 |
Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
Select-Object -ExpandProperty IPAddress
} catch {}

$primaryIP = $localIPs | Select-Object -First 1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SCCM Deployment Web GUI Started" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Server is accessible from network:" -ForegroundColor Yellow
Write-Host " Local: http://localhost:$Port" -ForegroundColor White
if ($primaryIP) {
Write-Host " Network: http://${primaryIP}:$Port" -ForegroundColor White
}
foreach ($ip in ($localIPs | Select-Object -Skip 1)) {
Write-Host " http://${ip}:$Port" -ForegroundColor Gray
}
Write-Host ""
Write-Host "IMPORTANT: Ensure Windows Firewall allows port $Port" -ForegroundColor Yellow
Write-Host "Run this command as Administrator to open the port:" -ForegroundColor Gray
Write-Host " New-NetFirewallRule -DisplayName 'SCCM Web GUI' -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try { Start-Process "http://localhost:$Port" } catch {}

#endregion

#region Main Loop — process SCCM deployments on the main thread

try {
while (-not $SharedState.StopServer) {

if ($SharedState.DeployRequest -and -not $SharedState.IsDeploying) {

$body = $SharedState.DeployRequest
$SharedState.DeployRequest = $null
$SharedState.IsDeploying = $true

try {
$config = $body | ConvertFrom-Json

# Clear log and write header for this run
$SharedState.LogMessages.Clear()
[void]$SharedState.LogMessages.Add("=== DEPLOYMENT REQUEST ===")
[void]$SharedState.LogMessages.Add("Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$SharedState.LogMessages.Add("Mode: $(if ($config.WhatIf) { 'WhatIf' } else { 'Deploy' })")
[void]$SharedState.LogMessages.Add("Application: $($config.AppName)")
[void]$SharedState.LogMessages.Add("Site: $($config.SiteCode) @ $($config.SiteServerFqdn)")
[void]$SharedState.LogMessages.Add("========================")
[void]$SharedState.LogMessages.Add("")

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
InstallCollectionName = $config.InstallCollectionName
UninstallCollectionName = $config.UninstallCollectionName
ApplicationFolder = $config.ApplicationFolder
CollectionFolder = $config.CollectionFolder
MaxRuntimeMins = $config.MaxRuntimeMins
CollectionCreationTimeoutMinutes = $config.CollectionCreationTimeoutMinutes
LogFilePath = $config.LogFilePath
Force = [bool]$config.Force
NoRollback = [bool]$config.NoRollback
VerboseLogging = [bool]$config.VerboseLogging
WhatIf = [bool]$config.WhatIf
}

Invoke-SCCMDeployment -Config $params

} catch {
Write-DeployLog "Fatal error: $_" -Level 'Error'
} finally {
[void]$SharedState.LogMessages.Add("")
[void]$SharedState.LogMessages.Add("=========================================")
[void]$SharedState.LogMessages.Add("DEPLOYMENT PROCESS FINISHED")
[void]$SharedState.LogMessages.Add("=========================================")
$SharedState.IsDeploying = $false
}
}

Start-Sleep -Milliseconds 200
}
} finally {
# Signal the HTTP server runspace to stop, then clean up
$SharedState.StopServer = $true
Start-Sleep -Milliseconds 700

try { $httpPs.Stop() } catch {}
try { $httpPs.Dispose() } catch {}
try { $httpRunspace.Close() } catch {}
try { $httpRunspace.Dispose() } catch {}

Write-Host "`nServer stopped." -ForegroundColor Yellow
}

#endregion
