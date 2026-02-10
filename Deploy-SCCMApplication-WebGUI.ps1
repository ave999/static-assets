<#
.SYNOPSIS
    Web-based GUI for SCCM Application Deployment

.DESCRIPTION
    Launches a local web server providing an HTML interface for deploying SCCM applications.
    Open your browser to http://localhost:8080 after running this script.

.NOTES
    Author: Web GUI wrapper for Deploy-SCCMApplication-Improved.ps1
    Version: 1.0
    Requires: PowerShell 5.1+, Modern web browser
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8080,

    [Parameter(Mandatory = $false)]
    [switch]$AllowRemoteAccess
)

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

#region HTTP Server Functions

function Get-ContentType {
    param([string]$Extension)

    $contentTypes = @{
        '.html' = 'text/html'
        '.css'  = 'text/css'
        '.js'   = 'application/javascript'
        '.json' = 'application/json'
        '.png'  = 'image/png'
        '.jpg'  = 'image/jpeg'
        '.ico'  = 'image/x-icon'
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
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SCCM Application Deployment Tool</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: "Segoe UI", Arial, sans-serif;
            background-color: #f5f7f8;
            color: #2d2d2d;
            min-height: 100vh;
            padding: 20px;
            line-height: 1.6;
        }

        .container {
            max-width: 1100px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0px 2px 6px rgba(0,0,0,0.08);
            overflow: hidden;
        }

        .header {
            background-color: #00594c;
            color: white;
            padding: 40px 20px;
            text-align: center;
        }

        .header h1 {
            font-size: 28px;
            margin-bottom: 10px;
            color: white;
            font-weight: 600;
        }

        .header p {
            opacity: 0.95;
            font-size: 14px;
        }

        .tabs {
            display: flex;
            background: #f5f5f5;
            border-bottom: 2px solid #ddd;
        }

        .tab {
            flex: 1;
            padding: 15px;
            text-align: center;
            cursor: pointer;
            background: #f5f5f5;
            border: none;
            font-size: 16px;
            transition: all 0.2s ease;
            font-weight: 600;
        }

        .tab:hover {
            background: #e7f4f1;
        }

        .tab.active {
            background: white;
            border-bottom: 3px solid #008361;
            color: #00594c;
        }

        .tab-content {
            display: none;
            padding: 30px;
            animation: fadeIn 0.3s;
        }

        .tab-content.active {
            display: block;
        }

        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }

        .form-group {
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: 600;
            color: #333;
        }

        .form-group input,
        .form-group select,
        .form-group textarea {
            width: 100%;
            padding: 10px;
            border: 2px solid #ddd;
            border-radius: 6px;
            font-size: 14px;
            transition: border-color 0.3s;
        }

        .form-group input:focus,
        .form-group select:focus,
        .form-group textarea:focus {
            outline: none;
            border-color: #008361;
        }

        .form-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }

        .checkbox-group {
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .checkbox-group input[type="checkbox"] {
            width: auto;
        }

        .fieldset {
            border: 2px solid #ddd;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            background: white;
        }

        .fieldset legend {
            padding: 0 10px;
            font-weight: 600;
            color: #00594c;
        }

        .actions {
            display: flex;
            gap: 15px;
            justify-content: center;
            padding: 30px;
            background: #f5f7f8;
            border-top: 2px solid #ddd;
        }

        .btn {
            padding: 12px 22px;
            border: none;
            border-radius: 4px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s ease;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }

        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        .btn-whatif {
            background-color: transparent;
            border: 2px solid #008361;
            color: #008361;
            padding: 10px 20px;
        }

        .btn-whatif:hover:not(:disabled) {
            background-color: #e7f4f1;
        }

        .btn-deploy {
            background-color: #008361;
            color: white;
        }

        .btn-deploy:hover:not(:disabled) {
            background-color: #006f4f;
        }

        .btn-stop {
            background: #e74c3c;
            color: white;
        }

        .btn-stop:hover:not(:disabled) {
            background: #c0392b;
        }

        .log-container {
            background: #1e1e1e;
            color: #00ff00;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: 13px;
            height: 500px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
        }

        .log-controls {
            margin-bottom: 15px;
            display: flex;
            gap: 10px;
        }

        .log-controls button {
            padding: 8px 15px;
            background: #008361;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-weight: 600;
            transition: background 0.2s ease;
        }

        .log-controls button:hover {
            background: #006f4f;
        }

        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
            margin-left: 10px;
        }

        .status-ready {
            background: #d4edda;
            color: #155724;
        }

        .status-deploying {
            background: #fff3cd;
            color: #856404;
        }

        .status-success {
            background: #d4edda;
            color: #155724;
        }

        .status-error {
            background: #f8d7da;
            color: #721c24;
        }

        .help-text {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }

        .required::after {
            content: " *";
            color: red;
        }

        .spinner {
            display: inline-block;
            width: 14px;
            height: 14px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s linear infinite;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>SCCM Application Deployment Tool</h1>
            <p>Automated deployment with real-time monitoring</p>
        </div>

        <div class="tabs">
            <button class="tab active" onclick="switchTab('config')">⚙️ Configuration</button>
            <button class="tab" onclick="switchTab('options')">🔧 Options</button>
            <button class="tab" onclick="switchTab('log')">📋 Execution Log</button>
        </div>

        <div id="config" class="tab-content active">
            <h2>Application Configuration</h2>

            <div class="form-row">
                <div class="form-group">
                    <label class="required">Application Name</label>
                    <input type="text" id="appName" value="" placeholder="e.g., MyApp_v1.0">
                    <div class="help-text">Unique name for the application in SCCM</div>
                </div>

                <div class="form-group">
                    <label>Deployment Type Name</label>
                    <input type="text" id="deployTypeName" value="" placeholder="e.g., MyApp_DEPLOY01">
                </div>
            </div>

            <div class="form-group">
                <label>Description</label>
                <input type="text" id="description" value="" placeholder="Application description">
            </div>

            <div class="form-row">
                <div class="form-group">
                    <label class="required">Site Code</label>
                    <input type="text" id="siteCode" value="" maxlength="3" placeholder="ABC">
                    <div class="help-text">3-letter SCCM site code</div>
                </div>

                <div class="form-group">
                    <label class="required">Site Server FQDN</label>
                    <input type="text" id="siteServer" value="" placeholder="sccm.domain.com">
                </div>
            </div>

            <fieldset class="fieldset">
                <legend>📁 Content Settings</legend>

                <div class="form-group">
                    <label class="required">Content Location (UNC Path)</label>
                    <input type="text" id="contentLocation" value="" placeholder="\\server\share\folder">
                    <div class="help-text">Network path to application source files (type the full UNC path manually)</div>
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label class="required">Install Command</label>
                        <input type="text" id="installCmd" value="" placeholder="setup.exe /silent">
                    </div>

                    <div class="form-group">
                        <label>Uninstall Command</label>
                        <input type="text" id="uninstallCmd" value="" placeholder="uninstall.exe /quiet">
                    </div>
                </div>

                <div class="form-group">
                    <label>Maximum Runtime (minutes)</label>
                    <input type="number" id="maxRuntime" value="60" min="1" max="720">
                </div>
            </fieldset>

            <fieldset class="fieldset">
                <legend>📦 Collections & Distribution</legend>

                <div class="form-group">
                    <label class="required">Limiting Collection</label>
                    <input type="text" id="limitingCollection" value="" placeholder="All Desktop and Server Clients">
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label>Install Collection</label>
                        <input type="text" id="installCollection" placeholder="(defaults to Application Name)">
                    </div>

                    <div class="form-group">
                        <label>Uninstall Collection</label>
                        <input type="text" id="uninstallCollection" placeholder="(defaults to AppName_Uninstall)">
                    </div>
                </div>

                <div class="form-group">
                    <label class="required">Distribution Point Group</label>
                    <input type="text" id="dpGroup" value="" placeholder="All Distribution Points">
                </div>
            </fieldset>

            <fieldset class="fieldset">
                <legend>📂 Console Organization</legend>

                <div class="form-row">
                    <div class="form-group">
                        <label>Application Folder Path</label>
                        <input type="text" id="appFolder" value="" placeholder="Applications\Production">
                    </div>

                    <div class="form-group">
                        <label>Collection Folder Path</label>
                        <input type="text" id="collectionFolder" value="" placeholder="Collections\Applications\Production">
                    </div>
                </div>
            </fieldset>
        </div>

        <div id="options" class="tab-content">
            <h2>Deployment Options</h2>

            <div class="form-group checkbox-group">
                <input type="checkbox" id="enableLogging" checked>
                <label for="enableLogging">Enable file logging</label>
            </div>

            <div class="form-group">
                <label>Log File Path</label>
                <input type="text" id="logPath" value="" placeholder="C:\Logs\deployment.log">
                <div class="help-text">Full path to log file (e.g., C:\Logs\deployment.log). Leave empty to skip file logging.</div>
            </div>

            <div class="form-group checkbox-group">
                <input type="checkbox" id="forceMode">
                <label for="forceMode">Force mode (skip confirmation prompts)</label>
            </div>

            <div class="form-group checkbox-group">
                <input type="checkbox" id="noRollback">
                <label for="noRollback">Disable automatic rollback on failure</label>
            </div>

            <div class="form-group">
                <label>Collection Creation Timeout (minutes)</label>
                <input type="number" id="collectionTimeout" value="5" min="1" max="30">
            </div>
        </div>

        <div id="log" class="tab-content">
            <h2>Execution Log <span id="statusBadge" class="status-badge status-ready">Ready</span></h2>

            <div class="log-controls">
                <button onclick="clearLog()">Clear Log</button>
                <button onclick="saveLog()">Save Log</button>
                <button onclick="refreshLog()">Refresh</button>
            </div>

            <div id="logContainer" class="log-container">Ready to deploy. Configure your settings and click "Deploy" or "WhatIf" to begin.</div>
        </div>

        <div class="actions">
            <button class="btn btn-whatif" id="btnWhatIf" onclick="startDeployment(true)">
                🧪 WhatIf (Test Run)
            </button>
            <button class="btn btn-deploy" id="btnDeploy" onclick="startDeployment(false)">
                🚀 Deploy
            </button>
        </div>
    </div>

    <script>
        let logRefreshInterval = null;

        function switchTab(tabName) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));

            event.target.classList.add('active');
            document.getElementById(tabName).classList.add('active');

            if (tabName === 'log') {
                startLogRefresh();
            } else {
                stopLogRefresh();
            }
        }

        function startLogRefresh() {
            refreshLog();
            if (!logRefreshInterval) {
                logRefreshInterval = setInterval(refreshLog, 1000);
            }
        }

        function stopLogRefresh() {
            if (logRefreshInterval) {
                clearInterval(logRefreshInterval);
                logRefreshInterval = null;
            }
        }

        function refreshLog() {
            fetch('/api/logs')
                .then(r => r.json())
                .then(data => {
                    const logContainer = document.getElementById('logContainer');
                    const wasAtBottom = logContainer.scrollHeight - logContainer.scrollTop === logContainer.clientHeight;

                    logContainer.textContent = data.logs.join('\n');

                    if (wasAtBottom) {
                        logContainer.scrollTop = logContainer.scrollHeight;
                    }

                    updateStatus(data.isDeploying);
                });
        }

        function updateStatus(isDeploying) {
            const badge = document.getElementById('statusBadge');
            const btnWhatIf = document.getElementById('btnWhatIf');
            const btnDeploy = document.getElementById('btnDeploy');

            if (isDeploying) {
                badge.className = 'status-badge status-deploying';
                badge.innerHTML = '<span class="spinner"></span> Deploying...';
                btnWhatIf.disabled = true;
                btnDeploy.disabled = true;
            } else {
                badge.className = 'status-badge status-ready';
                badge.textContent = 'Ready';
                btnWhatIf.disabled = false;
                btnDeploy.disabled = false;
            }
        }

        function clearLog() {
            fetch('/api/clear-log', { method: 'POST' })
                .then(() => refreshLog());
        }

        function saveLog() {
            const logs = document.getElementById('logContainer').textContent;
            const blob = new Blob([logs], { type: 'text/plain' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `sccm-deploy-${new Date().toISOString().replace(/:/g, '-')}.log`;
            a.click();
            URL.revokeObjectURL(url);
        }

        function validateInputs() {
            const errors = [];

            // Required fields with friendly names
            const required = {
                'appName': 'Application Name',
                'siteCode': 'Site Code',
                'siteServer': 'Site Server FQDN',
                'contentLocation': 'Content Location',
                'installCmd': 'Install Command',
                'limitingCollection': 'Limiting Collection',
                'dpGroup': 'Distribution Point Group'
            };

            // Check all required fields
            for (const [field, label] of Object.entries(required)) {
                const value = document.getElementById(field).value.trim();
                if (!value) {
                    errors.push(`• ${label} is required`);
                }
            }

            // Validate UNC path format
            const contentLoc = document.getElementById('contentLocation').value.trim();
            if (contentLoc && !contentLoc.startsWith('\\\\')) {
                errors.push('• Content Location must be a UNC path (e.g., \\\\server\\share\\folder)');
            }

            // Validate site code is 3 characters
            const siteCode = document.getElementById('siteCode').value.trim();
            if (siteCode && siteCode.length !== 3) {
                errors.push('• Site Code must be exactly 3 characters');
            }

            // Validate folder paths don't have illegal characters
            const appFolder = document.getElementById('appFolder').value.trim();
            const collFolder = document.getElementById('collectionFolder').value.trim();

            if (appFolder && /[<>:"|?*]/.test(appFolder)) {
                errors.push('• Application Folder Path contains illegal characters');
            }

            if (collFolder && /[<>:"|?*]/.test(collFolder)) {
                errors.push('• Collection Folder Path contains illegal characters');
            }

            // Show errors if any
            if (errors.length > 0) {
                alert('Please fix the following errors:\n\n' + errors.join('\n'));
                return false;
            }

            return true;
        }

        function getConfig() {
            return {
                AppName: document.getElementById('appName').value,
                Description: document.getElementById('description').value,
                SiteCode: document.getElementById('siteCode').value,
                SiteServerFqdn: document.getElementById('siteServer').value,
                ContentLocation: document.getElementById('contentLocation').value,
                InstallCommand: document.getElementById('installCmd').value,
                UninstallCommand: document.getElementById('uninstallCmd').value,
                DeploymentTypeName: document.getElementById('deployTypeName').value,
                DPGroupName: document.getElementById('dpGroup').value,
                LimitingCollectionName: document.getElementById('limitingCollection').value,
                InstallCollectionName: document.getElementById('installCollection').value || null,
                UninstallCollectionName: document.getElementById('uninstallCollection').value || null,
                ApplicationFolder: document.getElementById('appFolder').value,
                CollectionFolder: document.getElementById('collectionFolder').value,
                MaxRuntimeMins: parseInt(document.getElementById('maxRuntime').value),
                CollectionCreationTimeoutMinutes: parseInt(document.getElementById('collectionTimeout').value),
                LogFilePath: document.getElementById('enableLogging').checked ? (document.getElementById('logPath').value.trim() || null) : null,
                Force: document.getElementById('forceMode').checked,
                NoRollback: document.getElementById('noRollback').checked
            };
        }

        function startDeployment(whatIf) {
            if (!validateInputs()) {
                return;
            }

            const mode = whatIf ? 'WhatIf' : 'Deploy';
            const confirmed = confirm(`Start deployment in ${mode} mode?\n\nApplication: ${document.getElementById('appName').value}\nSite: ${document.getElementById('siteCode').value}`);

            if (!confirmed) {
                return;
            }

            const config = getConfig();
            config.WhatIf = whatIf;

            fetch('/api/deploy', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(config)
            })
            .then(r => r.json())
            .then(data => {
                if (data.success) {
                    switchTab('log');
                    document.querySelector('.tab:nth-child(3)').click();
                    startLogRefresh();
                } else {
                    alert('Failed to start deployment: ' + data.error);
                }
            })
            .catch(err => {
                alert('Error: ' + err);
            });
        }

        // Auto-refresh log when on log tab
        document.addEventListener('DOMContentLoaded', () => {
            const activeTab = document.querySelector('.tab-content.active');
            if (activeTab && activeTab.id === 'log') {
                startLogRefresh();
            }
        });
    </script>
</body>
</html>
'@
}

#endregion

#region API Handlers

function Handle-GetLogs {
    param([System.Net.HttpListenerContext]$Context)

    # Collect logs from active job if running
    if ($script:CurrentJobId -and (Get-Job -Id $script:CurrentJobId -ErrorAction SilentlyContinue)) {
        $job = Get-Job -Id $script:CurrentJobId

        # Get any new output from the job
        $output = Receive-Job -Id $script:CurrentJobId -Keep
        if ($output) {
            # Clear and rebuild log from job output
            $script:LogMessages = @()
            foreach ($line in $output) {
                $timestamp = Get-Date -Format 'HH:mm:ss'
                $script:LogMessages += "[$timestamp] $line"
            }
        }

        # Check if job finished
        if ($job.State -ne 'Running') {
            # Get final output
            $finalOutput = Receive-Job -Id $script:CurrentJobId
            if ($finalOutput) {
                $script:LogMessages = @()
                foreach ($line in $finalOutput) {
                    $timestamp = Get-Date -Format 'HH:mm:ss'
                    $script:LogMessages += "[$timestamp] $line"
                }
            }

            $script:LogMessages += ""
            $script:LogMessages += "========================================="
            if ($job.State -eq 'Completed') {
                $script:LogMessages += "DEPLOYMENT COMPLETED"
            } else {
                $script:LogMessages += "DEPLOYMENT FAILED OR WAS INTERRUPTED (State: $($job.State))"
            }
            $script:LogMessages += "========================================="

            Remove-Job -Id $script:CurrentJobId -Force -ErrorAction SilentlyContinue
            $script:IsDeploying = $false
            $script:CurrentJobId = $null
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
    if ($config.WhatIf) { $params.WhatIf = $true }

    # Start deployment in background
    $job = Start-Job -ScriptBlock {
        param($ScriptPath, $Params)
        & $ScriptPath @Params 2>&1
    } -ArgumentList $DeploymentScript, $params

    # Store job ID (not the object)
    $script:CurrentJobId = $job.Id

    # Add initial log message
    $script:LogMessages += "Starting deployment job (ID: $($job.Id))..."
    $script:LogMessages += "Waiting for output..."

    Send-HttpResponse -Context $Context -Content '{"success":true}' -ContentType 'application/json'
}

#endregion

# Start HTTP listener
$listener = New-Object System.Net.HttpListener

if ($AllowRemoteAccess) {
    # Bind to all network interfaces
    $listener.Prefixes.Add("http://+:$Port/")

    # Get local IP addresses
    $localIPs = Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
                Select-Object -ExpandProperty IPAddress

    $primaryIP = $localIPs | Select-Object -First 1
} else {
    # Localhost only (default, safer)
    $listener.Prefixes.Add("http://localhost:$Port/")
}

try {
    $listener.Start()

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "SCCM Deployment Web GUI Started" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if ($AllowRemoteAccess) {
        Write-Host "Server is accessible from network:" -ForegroundColor Yellow
        Write-Host "  Local:   http://localhost:$Port" -ForegroundColor White
        if ($primaryIP) {
            Write-Host "  Network: http://${primaryIP}:$Port" -ForegroundColor White
        }
        foreach ($ip in $localIPs) {
            if ($ip -ne $primaryIP) {
                Write-Host "           http://${ip}:$Port" -ForegroundColor Gray
            }
        }
        Write-Host ""
        Write-Host "IMPORTANT: Ensure Windows Firewall allows port $Port" -ForegroundColor Yellow
        Write-Host "Run this command as Administrator to open the port:" -ForegroundColor Gray
        Write-Host "  New-NetFirewallRule -DisplayName 'SCCM Web GUI' -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow" -ForegroundColor Cyan
    } else {
        Write-Host "Open your browser to: http://localhost:$Port" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Note: Only accessible from this computer." -ForegroundColor Gray
        Write-Host "Use -AllowRemoteAccess to enable network access." -ForegroundColor Gray
    }

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

    # Clean up any running jobs
    if ($script:CurrentJobId) {
        Stop-Job -Id $script:CurrentJobId -ErrorAction SilentlyContinue
        Remove-Job -Id $script:CurrentJobId -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`nServer stopped." -ForegroundColor Yellow
}
