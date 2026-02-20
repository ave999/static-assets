[CmdletBinding()]
param()

$Port               = 80
$SiteCode           = 'CM0'
$SiteServer         = 'WAZEU2PRDDE051.corp.internal.citizensbank.com'
$ErrorActionPreference = 'Stop'

#region Shared State

$SharedState = [hashtable]::Synchronized(@{
    LogMessages   = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    IsDeploying   = $false
    DeployRequest = $null
    StopServer    = $false
})

#endregion

#region HTTP Server Scriptblock (runs in background runspace)

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
        $Context.Response.ContentType     = "$ContentType; charset=utf-8"
        $Context.Response.StatusCode      = $StatusCode
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
        * { margin: 0; padding: 0; box-sizing: border-box; }

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
        .header h1 { font-size: 28px; margin-bottom: 10px; font-weight: 600; }
        .header p  { opacity: 0.95; font-size: 14px; }

        .tabs { display: flex; background: #f5f5f5; border-bottom: 2px solid #ddd; }
        .tab {
            flex: 1; padding: 15px; text-align: center; cursor: pointer;
            background: #f5f5f5; border: none; font-size: 16px;
            transition: all 0.2s ease; font-weight: 600;
        }
        .tab:hover { background: #e7f4f1; }
        .tab.active { background: white; border-bottom: 3px solid #008361; color: #00594c; }

        .tab-content { display: none; padding: 30px; animation: fadeIn 0.3s; }
        .tab-content.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }

        .form-group { margin-bottom: 20px; }
        .form-group label { display: block; margin-bottom: 5px; font-weight: 600; color: #333; }
        .form-group input, .form-group select, .form-group textarea {
            width: 100%; padding: 10px; border: 2px solid #ddd;
            border-radius: 6px; font-size: 14px; transition: border-color 0.3s;
        }
        .form-group input:focus, .form-group select:focus, .form-group textarea:focus {
            outline: none; border-color: #008361;
        }

        .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }

        .checkbox-group { display: flex; align-items: center; gap: 10px; }
        .checkbox-group input[type="checkbox"] { width: auto; }

        .fieldset {
            border: 2px solid #ddd; border-radius: 8px;
            padding: 20px; margin-bottom: 20px; background: white;
        }
        .fieldset legend { padding: 0 10px; font-weight: 600; color: #00594c; }

        .fieldset .fieldset { border-color: #e8e8e8; margin-top: 15px; margin-bottom: 0; }
        .fieldset .fieldset legend { color: #555; font-size: 13px; }

        .actions {
            display: flex; gap: 15px; justify-content: center;
            padding: 30px; background: #f5f7f8; border-top: 2px solid #ddd;
        }

        .btn {
            padding: 12px 22px; border: none; border-radius: 4px;
            font-size: 16px; font-weight: 600; cursor: pointer;
            transition: background 0.2s ease; display: inline-flex;
            align-items: center; gap: 8px;
        }
        .btn:disabled { opacity: 0.5; cursor: not-allowed; }

        .btn-whatif {
            background-color: transparent; border: 2px solid #008361;
            color: #008361; padding: 10px 20px;
        }
        .btn-whatif:hover:not(:disabled) { background-color: #e7f4f1; }

        .btn-deploy { background-color: #008361; color: white; }
        .btn-deploy:hover:not(:disabled) { background-color: #006f4f; }

        .log-container {
            background: #1e1e1e; color: #00ff00; padding: 20px;
            border-radius: 8px; font-family: 'Consolas', 'Monaco', monospace;
            font-size: 13px; height: 500px; overflow-y: auto;
            white-space: pre-wrap; word-wrap: break-word;
        }

        .log-controls { margin-bottom: 15px; display: flex; gap: 10px; }
        .log-controls button {
            padding: 8px 15px; background: #008361; color: white;
            border: none; border-radius: 4px; cursor: pointer;
            font-weight: 600; transition: background 0.2s ease;
        }
        .log-controls button:hover { background: #006f4f; }

        .status-badge {
            display: inline-block; padding: 5px 15px; border-radius: 20px;
            font-size: 12px; font-weight: bold; margin-left: 10px;
        }
        .status-ready    { background: #d4edda; color: #155724; }
        .status-deploying{ background: #fff3cd; color: #856404; }

        .help-text { font-size: 12px; color: #666; margin-top: 5px; }
        .required::after { content: " *"; color: red; }

        .input-error { border-color: #e74c3c !important; background-color: #fef5f5 !important; }
        .error-message { color: #e74c3c; font-size: 12px; margin-top: 5px; display: none; }
        .error-message.visible { display: block; }

        .validation-summary {
            background-color: #fef5f5; border: 2px solid #e74c3c;
            border-radius: 6px; padding: 15px; margin-bottom: 20px; display: none;
        }
        .validation-summary.visible { display: block; }
        .validation-summary h3 { color: #e74c3c; margin-bottom: 10px; font-size: 16px; }
        .validation-summary ul { margin: 0; padding-left: 20px; }
        .validation-summary li { color: #721c24; margin-bottom: 5px; }

        .spinner {
            display: inline-block; width: 14px; height: 14px;
            border: 2px solid rgba(255,255,255,0.3); border-radius: 50%;
            border-top-color: white; animation: spin 1s linear infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>SCCM Application Deployment Tool</h1>
        <p>Automated deployment with real-time monitoring</p>
    </div>

    <div class="tabs">
        <button class="tab active" onclick="switchTab('config')">Configuration</button>
        <button class="tab" onclick="switchTab('options')">Options</button>
        <button class="tab" onclick="switchTab('log')">Execution Log</button>
    </div>

    <!-- ═══════════════════════════════════════ CONFIG TAB ═══════════════════════════════════════ -->
    <div id="config" class="tab-content active">
        <h2>Application Configuration</h2>

        <div id="validationSummary" class="validation-summary">
            <h3>Please fix the following errors:</h3>
            <ul id="validationErrors"></ul>
        </div>

        <div class="form-row">
            <div class="form-group">
                <label class="required">Application Name</label>
                <input type="text" id="appName" placeholder="e.g., MyApp_v1.0">
                <div class="error-message" id="appName-error">Application Name is required</div>
                <div class="help-text">Unique name for the application in SCCM</div>
            </div>
            <div class="form-group">
                <label>Deployment Type Name</label>
                <input type="text" id="deployTypeName" placeholder="(defaults to AppName_Install)">
            </div>
        </div>

        <div class="form-group">
            <label>Description</label>
            <input type="text" id="description" placeholder="Application description">
        </div>

        <fieldset class="fieldset">
            <legend>Content Settings</legend>
            <div class="form-group">
                <label class="required">Content Location (UNC Path)</label>
                <input type="text" id="contentLocation" placeholder="\\server\share\folder">
                <div class="error-message" id="contentLocation-error">Content Location is required and must be a UNC path (\\server\share\folder)</div>
                <div class="help-text">Network path to application source files</div>
            </div>
            <div class="form-row">
                <div class="form-group">
                    <label class="required">Install Command</label>
                    <input type="text" id="installCmd" placeholder="setup.exe /silent">
                    <div class="error-message" id="installCmd-error">Install Command is required</div>
                </div>
                <div class="form-group">
                    <label>Uninstall Command</label>
                    <input type="text" id="uninstallCmd" placeholder="uninstall.exe /quiet">
                </div>
            </div>
            <div class="form-group">
                <label>Maximum Runtime (minutes)</label>
                <input type="number" id="maxRuntime" value="60" min="1" max="720">
            </div>
        </fieldset>

        <fieldset class="fieldset">
            <legend>Collections &amp; Distribution</legend>
            <div class="form-group">
                <label class="required">Limiting Collection</label>
                <input type="text" id="limitingCollection" placeholder="All Desktop and Server Clients">
                <div class="error-message" id="limitingCollection-error">Limiting Collection is required</div>
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
                <label>Distribution Point Group</label>
                <input type="text" value="All Datacenter Distribution Points" disabled style="background:#f0f0f0;color:#555;cursor:not-allowed">
                <div class="help-text">Hardcoded — content always distributes to All Datacenter Distribution Points.</div>
            </div>
        </fieldset>

        <fieldset class="fieldset">
            <legend>Console Organization</legend>
            <div class="form-row">
                <div class="form-group">
                    <label>Application Folder Path</label>
                    <input type="text" value="DSK\_BUILD" disabled style="background:#f0f0f0;color:#555;cursor:not-allowed">
                </div>
                <div class="form-group">
                    <label>Collection Folder Path</label>
                    <input type="text" value="DSK\Application Deployments\_STAGING" disabled style="background:#f0f0f0;color:#555;cursor:not-allowed">
                </div>
            </div>
        </fieldset>

        <fieldset class="fieldset">
            <legend>Detection Methods</legend>

            <div class="form-group">
                <label>Registry Uninstall Key Name</label>
                <input type="text" id="detectionRegKey" placeholder="(defaults to Application Name)">
                <div class="help-text">Key name under HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ (both 64-bit and 32-bit paths are checked)</div>
            </div>

            <fieldset class="fieldset">
                <legend>Registry Value Detection (optional)</legend>
                <div class="form-row">
                    <div class="form-group">
                        <label>Value Name</label>
                        <input type="text" id="detectionRegValueName" placeholder="DisplayVersion">
                    </div>
                    <div class="form-group">
                        <label>Data Type</label>
                        <select id="detectionRegDataType">
                            <option value="">-- select --</option>
                            <option value="String">String</option>
                            <option value="Integer">Integer</option>
                            <option value="Version">Version</option>
                            <option value="Int64">Int64</option>
                            <option value="Double">Double</option>
                            <option value="Boolean">Boolean</option>
                        </select>
                    </div>
                </div>
                <div class="form-row">
                    <div class="form-group">
                        <label>Operator</label>
                        <select id="detectionRegOperator">
                            <option value="">-- select --</option>
                            <option value="Equals">Equals</option>
                            <option value="NotEquals">NotEquals</option>
                            <option value="GreaterThan">GreaterThan</option>
                            <option value="GreaterEquals">GreaterEquals</option>
                            <option value="LessThan">LessThan</option>
                            <option value="LessEquals">LessEquals</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label>Expected Value</label>
                        <input type="text" id="detectionRegExpectedValue" placeholder="1.2.3.4">
                    </div>
                </div>
                <div class="help-text">Leave blank to check key existence only. All four fields are required for a value comparison.</div>
            </fieldset>

            <fieldset class="fieldset">
                <legend>File Detection (optional)</legend>
                <div class="form-row">
                    <div class="form-group">
                        <label>File Path</label>
                        <input type="text" id="detectionFilePath" placeholder="C:\Program Files\MyApp">
                    </div>
                    <div class="form-group">
                        <label>File Name</label>
                        <input type="text" id="detectionFileName" placeholder="App.exe">
                    </div>
                </div>
                <div class="form-group">
                    <label>Minimum Version <span style="font-weight:normal;color:#666">(leave blank to check existence only)</span></label>
                    <input type="text" id="detectionFileVersion" placeholder="1.0.0.0">
                </div>
            </fieldset>

            <fieldset class="fieldset">
                <legend>Directory Detection (optional)</legend>
                <div class="form-row">
                    <div class="form-group">
                        <label>Directory Path</label>
                        <input type="text" id="detectionDirPath" placeholder="%ProgramFiles%\MyApp">
                    </div>
                    <div class="form-group">
                        <label>Directory Name</label>
                        <input type="text" id="detectionDirName" placeholder="MyApp">
                    </div>
                </div>
            </fieldset>

            <fieldset class="fieldset">
                <legend>Windows Installer Detection (optional)</legend>
                <div class="form-row">
                    <div class="form-group">
                        <label>Product Code</label>
                        <input type="text" id="detectionMsiProductCode" placeholder="{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}">
                    </div>
                    <div class="form-group">
                        <label>Version Operator</label>
                        <select id="detectionMsiVersionOp">
                            <option value="Exists">Exists (no version check)</option>
                            <option value="Equals">Equals</option>
                            <option value="GreaterThan">GreaterThan</option>
                            <option value="GreaterEquals">GreaterEquals</option>
                            <option value="LessThan">LessThan</option>
                            <option value="LessEquals">LessEquals</option>
                        </select>
                    </div>
                </div>
                <div class="form-group">
                    <label>Product Version <span style="font-weight:normal;color:#666">(required when operator is not Exists)</span></label>
                    <input type="text" id="detectionMsiVersion" placeholder="1.2.3.4">
                </div>
                <div class="help-text">Uses the Windows Installer (MSI) product registration database — the most reliable detection for MSI-based applications. Leave Product Code blank to skip.</div>
            </fieldset>
        </fieldset>
    </div>

    <!-- ═══════════════════════════════════════ OPTIONS TAB ══════════════════════════════════════ -->
    <div id="options" class="tab-content">
        <h2>Deployment Options</h2>

        <div class="form-group checkbox-group">
            <input type="checkbox" id="enableLogging" checked>
            <label for="enableLogging">Enable file logging</label>
        </div>
        <div class="form-group">
            <label>Log File Path</label>
            <input type="text" id="logPath" placeholder="C:\Logs\deployment.log">
            <div class="help-text">Full path to log file. Leave empty to skip file logging.</div>
        </div>
        <div class="form-group checkbox-group">
            <input type="checkbox" id="forceMode">
            <label for="forceMode">Force mode (skip confirmation prompts)</label>
        </div>
        <div class="form-group checkbox-group">
            <input type="checkbox" id="noRollback">
            <label for="noRollback">Disable automatic rollback on failure</label>
        </div>
        <div class="form-group checkbox-group">
            <input type="checkbox" id="verboseLogging" checked>
            <label for="verboseLogging">Enable verbose logging (recommended during testing)</label>
        </div>
        <div class="form-group">
            <label>Collection Creation Timeout (minutes)</label>
            <input type="number" id="collectionTimeout" value="5" min="1" max="30">
        </div>
    </div>

    <!-- ════════════════════════════════════════ LOG TAB ════════════════════════════════════════ -->
    <div id="log" class="tab-content">
        <h2>Execution Log <span id="statusBadge" class="status-badge status-ready">Ready</span></h2>

        <div class="log-controls">
            <button onclick="clearLog()">Clear Log</button>
            <button onclick="saveLog()">Save Log</button>
            <button onclick="refreshLog()">Refresh</button>
            <button onclick="forceReset()" id="btnReset" style="background:#e74c3c;display:none;" title="Use if the deployment is stuck and the script is no longer responding">Force Reset</button>
        </div>

        <div id="logContainer" class="log-container">Ready to deploy. Configure your settings and click "Deploy" or "WhatIf" to begin.</div>
    </div>

    <div class="actions">
        <button class="btn btn-whatif" id="btnWhatIf" onclick="startDeployment(true)">WhatIf (Test Run)</button>
        <button class="btn btn-deploy"  id="btnDeploy"  onclick="startDeployment(false)">Deploy</button>
    </div>
</div>

<script>
    let logRefreshInterval = null;
    let validationErrors   = {};

    const requiredFields = {
        'appName':           'Application Name',
        'contentLocation':   'Content Location',
        'installCmd':        'Install Command',
        'limitingCollection':'Limiting Collection'
    };

    function validateField(fieldId) {
        const field    = document.getElementById(fieldId);
        const errorDiv = document.getElementById(fieldId + '-error');
        const value    = field.value.trim();
        let isValid    = true;
        let errorMessage = '';

        if (requiredFields[fieldId] && !value) {
            isValid = false;
            errorMessage = requiredFields[fieldId] + ' is required';
        }
        if (fieldId === 'contentLocation' && value && !value.startsWith('\\\\')) {
            isValid = false;
            errorMessage = 'Content Location must be a UNC path (e.g., \\\\server\\share\\folder)';
        }

        if (isValid) {
            field.classList.remove('input-error');
            if (errorDiv) errorDiv.classList.remove('visible');
            delete validationErrors[fieldId];
        } else {
            field.classList.add('input-error');
            if (errorDiv) { errorDiv.textContent = errorMessage; errorDiv.classList.add('visible'); }
            validationErrors[fieldId] = errorMessage;
        }

        updateValidationSummary();
        updateButtonStates();
        return isValid;
    }

    function validateAllFields() {
        validationErrors = {};
        let allValid = true;
        for (const fieldId in requiredFields) {
            if (!validateField(fieldId)) allValid = false;
        }
        return allValid;
    }

    function updateValidationSummary() {
        const summary    = document.getElementById('validationSummary');
        const errorList  = document.getElementById('validationErrors');
        const errorCount = Object.keys(validationErrors).length;
        if (errorCount > 0) {
            errorList.innerHTML = '';
            for (const fieldId in validationErrors) {
                const li = document.createElement('li');
                li.textContent = validationErrors[fieldId];
                errorList.appendChild(li);
            }
            summary.classList.add('visible');
        } else {
            summary.classList.remove('visible');
        }
    }

    function updateButtonStates() {
        const hasErrors   = Object.keys(validationErrors).length > 0;
        const isDeploying = document.getElementById('statusBadge').classList.contains('status-deploying');
        document.getElementById('btnWhatIf').disabled = hasErrors || isDeploying;
        document.getElementById('btnDeploy').disabled  = hasErrors || isDeploying;
    }

    function switchTab(tabName) {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
        const tabs = document.querySelectorAll('.tab');
        tabs.forEach(tab => {
            if (tab.textContent.includes(tabName === 'config' ? 'Configuration' : tabName === 'options' ? 'Options' : 'Log'))
                tab.classList.add('active');
        });
        document.getElementById(tabName).classList.add('active');
        if (tabName === 'log') startLogRefresh(); else stopLogRefresh();
    }

    function startLogRefresh() {
        refreshLog();
        if (!logRefreshInterval) logRefreshInterval = setInterval(refreshLog, 1000);
    }

    function stopLogRefresh() {
        if (logRefreshInterval) { clearInterval(logRefreshInterval); logRefreshInterval = null; }
    }

    function refreshLog() {
        fetch('/api/logs')
            .then(r => r.json())
            .then(data => {
                const logContainer = document.getElementById('logContainer');
                const wasAtBottom  = logContainer.scrollHeight - logContainer.scrollTop === logContainer.clientHeight;
                logContainer.textContent = data.logs.join('\n');
                if (wasAtBottom) logContainer.scrollTop = logContainer.scrollHeight;
                updateStatus(data.isDeploying);
            })
            .catch(() => { /* transient poll failure — ignore, next tick will retry */ });
    }

    function updateStatus(isDeploying) {
        const badge    = document.getElementById('statusBadge');
        const resetBtn = document.getElementById('btnReset');
        if (isDeploying) {
            badge.className = 'status-badge status-deploying';
            badge.innerHTML = '<span class="spinner"></span> Deploying...';
            if (resetBtn) resetBtn.style.display = 'inline-block';
        } else {
            badge.className = 'status-badge status-ready';
            badge.textContent = 'Ready';
            if (resetBtn) resetBtn.style.display = 'none';
        }
        updateButtonStates();
    }

    function forceReset() {
        if (!confirm('Force-reset the deployment state?\n\nOnly use this if the script crashed or was killed mid-deployment and the UI is stuck on "Deploying...". This does NOT undo any SCCM changes already made.'))
            return;
        fetch('/api/reset', { method: 'POST' })
            .then(r => r.json())
            .then(() => refreshLog())
            .catch(err => alert('Reset failed: ' + err));
    }

    function clearLog() {
        fetch('/api/clear-log', { method: 'POST' }).then(() => refreshLog());
    }

    function saveLog() {
        const logs = document.getElementById('logContainer').textContent;
        const blob = new Blob([logs], { type: 'text/plain' });
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href     = url;
        a.download = 'sccm-deploy-' + new Date().toISOString().replace(/:/g, '-') + '.log';
        a.click();
        URL.revokeObjectURL(url);
    }

    function validateInputs() {
        const allValid  = validateAllFields();
        if (!allValid) { switchTab('config'); return false; }
        return true;
    }

    function getConfig() {
        return {
            AppName:                         document.getElementById('appName').value,
            Description:                     document.getElementById('description').value,
            SiteCode:                        'CM0',
            SiteServerFqdn:                  'WAZEU2PRDDE051.corp.internal.citizensbank.com',
            ContentLocation:                 document.getElementById('contentLocation').value,
            InstallCommand:                  document.getElementById('installCmd').value,
            UninstallCommand:                document.getElementById('uninstallCmd').value,
            DeploymentTypeName:              document.getElementById('deployTypeName').value,
            LimitingCollectionName:          document.getElementById('limitingCollection').value,
            InstallCollectionName:           document.getElementById('installCollection').value || null,
            UninstallCollectionName:         document.getElementById('uninstallCollection').value || null,
            MaxRuntimeMins:                  parseInt(document.getElementById('maxRuntime').value),
            CollectionCreationTimeoutMinutes:parseInt(document.getElementById('collectionTimeout').value),
            LogFilePath:                     document.getElementById('enableLogging').checked ? (document.getElementById('logPath').value.trim() || null) : null,
            Force:                           document.getElementById('forceMode').checked,
            NoRollback:                      document.getElementById('noRollback').checked,
            VerboseLogging:                  document.getElementById('verboseLogging').checked,
            // Detection methods
            DetectionRegKeyName:      document.getElementById('detectionRegKey').value.trim()           || null,
            DetectionRegValueName:    document.getElementById('detectionRegValueName').value.trim()     || null,
            DetectionRegDataType:     document.getElementById('detectionRegDataType').value             || null,
            DetectionRegOperator:     document.getElementById('detectionRegOperator').value             || null,
            DetectionRegExpectedValue:document.getElementById('detectionRegExpectedValue').value.trim() || null,
            DetectionFilePath:        document.getElementById('detectionFilePath').value.trim()         || null,
            DetectionFileName:        document.getElementById('detectionFileName').value.trim()         || null,
            DetectionFileVersion:     document.getElementById('detectionFileVersion').value.trim()      || null,
            DetectionDirPath:         document.getElementById('detectionDirPath').value.trim()          || null,
            DetectionDirName:         document.getElementById('detectionDirName').value.trim()          || null,
            DetectionMsiProductCode:  document.getElementById('detectionMsiProductCode').value.trim()   || null,
            DetectionMsiVersionOp:    document.getElementById('detectionMsiVersionOp').value            || 'Exists',
            DetectionMsiVersion:      document.getElementById('detectionMsiVersion').value.trim()       || null
        };
    }

    function startDeployment(whatIf) {
        if (!validateInputs()) return;
        const mode      = whatIf ? 'WhatIf' : 'Deploy';
        const appName   = document.getElementById('appName').value;
        const confirmed = confirm('Start deployment in ' + mode + ' mode?\n\nApplication: ' + appName + '\nSite: CM0 @ WAZEU2PRDDE051.corp.internal.citizensbank.com');
        if (!confirmed) return;

        const config  = getConfig();
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
        .catch(err => alert('Error: ' + err));
    }

    document.addEventListener('DOMContentLoaded', () => {
        for (const fieldId in requiredFields) {
            const field = document.getElementById(fieldId);
            if (field) {
                field.addEventListener('blur',  () => validateField(fieldId));
                field.addEventListener('input', () => { if (field.value.trim()) validateField(fieldId); });
            }
        }
        validateAllFields();
        const activeTab = document.querySelector('.tab-content.active');
        if (activeTab && activeTab.id === 'log') startLogRefresh();
    });
</script>
</body>
</html>
'@
    }

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$Port/")
    $listener.Start()

    while (-not $SharedState.StopServer) {
        try {
            $ar = $listener.BeginGetContext($null, $null)
            while (-not $ar.AsyncWaitHandle.WaitOne(500)) {
                if ($SharedState.StopServer) { break }
            }
            if ($SharedState.StopServer) { break }

            $context = $listener.EndGetContext($ar)
            $path    = $context.Request.Url.LocalPath

            try {
                switch -Regex ($path) {
                    '^/$' {
                        Send-HttpResponse -Context $context -Content (Get-HTMLPage) -ContentType 'text/html'
                    }
                    '^/api/logs$' {
                        $json = @{
                            logs        = @($SharedState.LogMessages)
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
                        $SharedState.IsDeploying   = $false
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
                # Always respond with JSON so the browser's r.json() call doesn't blow up.
                # Sending text/html (the Send-HttpResponse default) caused the frontend to
                # receive <!DOCTYPE … or plain text and throw "not valid JSON".
                $errJson = "{{""success"":false,""error"":""{0}""}}" -f ("$_" -replace '"','\"')
                try { Send-HttpResponse -Context $context -Content $errJson -ContentType 'application/json' -StatusCode 500 } catch {}
            }
        } catch [System.Net.HttpListenerException] {
            break
        } catch {}
    }

    try { $listener.Stop()  } catch {}
    try { $listener.Close() } catch {}
}

#endregion

#region Deployment Logic (runs on the main thread)

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
    $prefix    = switch ($Level) {
        'Step'    { '[STEP]' }
        'Success' { '[ OK ]' }
        'Warning' { '[WARN]' }
        'Error'   { '[FAIL]' }
        default   { '[INFO]' }
    }
    $line = "[$timestamp] $prefix $Message"
    [void]$script:SharedState.LogMessages.Add($line)
    Write-Host $line
}

function Invoke-SCCMDeployment {
    param([hashtable]$Config)

    # Extract parameters
    $AppName                          = $Config.AppName
    $Description                      = if ($Config.Description) { $Config.Description } else { "" }
    $SiteCode                         = $Config.SiteCode
    $SiteServerFqdn                   = $Config.SiteServerFqdn
    $ContentLocation                  = $Config.ContentLocation
    $InstallCommand                   = $Config.InstallCommand
    $UninstallCommand                 = if ($Config.UninstallCommand) { $Config.UninstallCommand } else { "" }
    $DeploymentTypeName               = $Config.DeploymentTypeName
    $DPGroupName                      = 'All Datacenter Distribution Points'
    $LimitingCollectionName           = $Config.LimitingCollectionName
    $InstallCollectionName            = $Config.InstallCollectionName
    $UninstallCollectionName          = $Config.UninstallCollectionName
    $ApplicationFolder                = 'DSK\_BUILD'
    $CollectionFolder                 = 'DSK\Application Deployments\_STAGING'
    $MaxRuntimeMins                   = if ($Config.MaxRuntimeMins) { $Config.MaxRuntimeMins } else { 60 }
    $CollectionCreationTimeoutMinutes = if ($Config.CollectionCreationTimeoutMinutes) { $Config.CollectionCreationTimeoutMinutes } else { 5 }
    $LogFilePath                      = $Config.LogFilePath
    $Force                            = [bool]$Config.Force
    $NoRollback                       = [bool]$Config.NoRollback
    $VerboseLogging                   = [bool]$Config.VerboseLogging
    $WhatIf                           = [bool]$Config.WhatIf

    # Detection method parameters
    $DetectionRegKeyName      = if ($Config.DetectionRegKeyName) { $Config.DetectionRegKeyName } else { $AppName }
    $DetectionRegValueName    = $Config.DetectionRegValueName
    $DetectionRegDataType     = $Config.DetectionRegDataType
    $DetectionRegOperator     = $Config.DetectionRegOperator
    $DetectionRegExpectedValue= $Config.DetectionRegExpectedValue
    $DetectionFilePath        = $Config.DetectionFilePath
    $DetectionFileName        = $Config.DetectionFileName
    $DetectionFileVersion     = $Config.DetectionFileVersion
    $DetectionDirPath         = $Config.DetectionDirPath
    $DetectionDirName         = $Config.DetectionDirName
    $DetectionMsiProductCode  = $Config.DetectionMsiProductCode
    $DetectionMsiVersionOp    = if ($Config.DetectionMsiVersionOp) { $Config.DetectionMsiVersionOp } else { 'Exists' }
    $DetectionMsiVersion      = $Config.DetectionMsiVersion

    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($DeploymentTypeName))     { $DeploymentTypeName     = "${AppName}_Install"    }
    if ([string]::IsNullOrWhiteSpace($InstallCollectionName))  { $InstallCollectionName  = $AppName               }
    if ([string]::IsNullOrWhiteSpace($UninstallCollectionName)){ $UninstallCollectionName = "${AppName}_Uninstall" }

    $createdObjects = @{ Application = $null; Collections = @(); Deployments = @() }

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
        param([string]$Name, [scriptblock]$Script, [switch]$ContinueOnError)
        Write-Log -Message $Name -Level 'Step'
        try {
            if ($VerboseLogging) {
                $verboseOutput = & $Script 4>&1 3>&1 2>&1
                foreach ($line in $verboseOutput) {
                    if ($line) { Write-Log -Message "  [VERBOSE] $line" -Level 'Info' }
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
        if ($NoRollback) { Write-Log "Rollback disabled." -Level 'Warning'; return }
        Write-Log "Initiating rollback..." -Level 'Warning'
        foreach ($deployment in $createdObjects.Deployments) {
            try { Remove-CMApplicationDeployment -DeploymentId $deployment -Force -ErrorAction Stop }
            catch { Write-Log "Failed to remove deployment ${deployment}: $_" -Level 'Error' }
        }
        foreach ($collection in $createdObjects.Collections) {
            try { Remove-CMDeviceCollection -Name $collection -Force -ErrorAction Stop }
            catch { Write-Log "Failed to remove collection ${collection}: $_" -Level 'Error' }
        }
        if ($createdObjects.Application) {
            try { Remove-CMApplication -Name $createdObjects.Application -Force -ErrorAction Stop }
            catch { Write-Log "Failed to remove application: $_" -Level 'Error' }
        }
        Write-Log "Rollback completed. Verify SCCM console for any remaining objects." -Level 'Warning'
    }

    try {
        $originalLocation = Get-Location

        Write-Log "========================================"
        Write-Log "SCCM Application Deployment Script"
        Write-Log "Application: $AppName"
        Write-Log "Site: $SiteCode ($SiteServerFqdn)"
        Write-Log "========================================"
        if ($WhatIf) { Write-Log "Running in WhatIf mode - no changes will be made" -Level 'Warning' }

        if ($VerboseLogging -or $WhatIf) {
            Write-Log ""
            Write-Log "=== PARAMETER VALUES ==="
            Write-Log "AppName: $AppName"
            Write-Log "Description: $Description"
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
            Write-Log "DetectionRegKeyName: $DetectionRegKeyName"
            Write-Log "DetectionRegValueName: $DetectionRegValueName"
            Write-Log "DetectionRegDataType: $DetectionRegDataType"
            Write-Log "DetectionRegOperator: $DetectionRegOperator"
            Write-Log "DetectionRegExpectedValue: $DetectionRegExpectedValue"
            Write-Log "DetectionFilePath: $DetectionFilePath"
            Write-Log "DetectionFileName: $DetectionFileName"
            Write-Log "DetectionFileVersion: $DetectionFileVersion"
            Write-Log "DetectionDirPath: $DetectionDirPath"
            Write-Log "DetectionDirName: $DetectionDirName"
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
                if (-not (Test-Path $installFile)) { throw "Installation command file not found: $installFile" }
                Write-Log "Install file found"
            }

            if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
                if ($UninstallCommand -notmatch '%.*%') {
                    $uninstallFile = Join-Path $ContentLocation $UninstallCommand
                    if (-not (Test-Path $uninstallFile)) {
                        Write-Log "Uninstall command file not found: $uninstallFile (continuing)" -Level 'Warning'
                    }
                }
            }
        }

        #--- Connect to SCCM site ---
        Invoke-Step -Name "Connect to SCCM site $SiteCode" -Script {
            if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
                Write-Log "CMSite drive not found — creating ${SiteCode}: -> $SiteServerFqdn"
                New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServerFqdn -ErrorAction Stop | Out-Null
            }
            Set-Location "$($SiteCode):\" -ErrorAction Stop
        }

        try {
            #--- Remove existing application ---
            Invoke-Step -Name "Check and remove existing application '$AppName'" -Script {
                # Get-CMApplicationDeployment can throw a terminating ArgumentNullException
                # internally (null WMI property used as a dictionary key). -ErrorAction
                # SilentlyContinue only suppresses non-terminating errors, so we must
                # use try/catch here. Treat any such failure as "no deployments found".
                $existingDeployments = $null
                try {
                    $existingDeployments = Get-CMApplicationDeployment -Name $AppName -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "Could not query existing deployments (non-fatal, assuming none): $_" -Level 'Warning'
                }
                if ($existingDeployments) {
                    Write-Log "Found $($existingDeployments.Count) existing deployment(s)"
                    if (-not $WhatIf) {
                        foreach ($dep in $existingDeployments) {
                            Remove-CMApplicationDeployment -InputObject $dep -Force -ErrorAction Stop
                            Write-Log "Removed deployment to: $($dep.CollectionName)" -Level 'Success'
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

            #--- Create application ---
            Invoke-Step -Name "Create application '$AppName'" -Script {
                if (-not $WhatIf) {
                    New-CMApplication -Name $AppName -Description $Description -ErrorAction Stop | Out-Null
                    $createdObjects.Application = $AppName
                } else {
                    Write-Log "[WHATIF] Would create application '$AppName'"
                }
            }

            #--- Build detection clauses ---
            Write-Log "Building detection rules" -Level 'Step'

            $detectionClauses = @()

            # Registry detection — value comparison when all four fields are supplied,
            # key-existence only otherwise.
            $regHasValueDetection = (
                -not [string]::IsNullOrWhiteSpace($DetectionRegValueName) -and
                -not [string]::IsNullOrWhiteSpace($DetectionRegDataType) -and
                -not [string]::IsNullOrWhiteSpace($DetectionRegOperator) -and
                -not [string]::IsNullOrWhiteSpace($DetectionRegExpectedValue)
            )

            if ($regHasValueDetection) {
                Write-Log "Registry value detection: $DetectionRegKeyName\$DetectionRegValueName $DetectionRegOperator '$DetectionRegExpectedValue' ($DetectionRegDataType)"
                # 64-bit registry value
                $detectionClauses += New-CMDetectionClauseRegistryKeyValue `
                    -Hive LocalMachine `
                    -Is64Bit `
                    -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName" `
                    -ValueName $DetectionRegValueName `
                    -PropertyType $DetectionRegDataType `
                    -ExpressionOperator $DetectionRegOperator `
                    -Value `
                    -ExpectedValue $DetectionRegExpectedValue
                # 32-bit (WOW64) registry value
                $detectionClauses += New-CMDetectionClauseRegistryKeyValue `
                    -Hive LocalMachine `
                    -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName" `
                    -ValueName $DetectionRegValueName `
                    -PropertyType $DetectionRegDataType `
                    -ExpressionOperator $DetectionRegOperator `
                    -Value `
                    -ExpectedValue $DetectionRegExpectedValue
            } else {
                Write-Log "Registry key existence detection: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName"
                # 64-bit key existence
                $detectionClauses += New-CMDetectionClauseRegistryKey `
                    -Hive LocalMachine `
                    -Is64Bit `
                    -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName"
                # 32-bit (WOW64) key existence
                $detectionClauses += New-CMDetectionClauseRegistryKey `
                    -Hive LocalMachine `
                    -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName"
            }

            # File detection (optional — only added when both path and filename are provided)
            if (-not [string]::IsNullOrWhiteSpace($DetectionFilePath) -and -not [string]::IsNullOrWhiteSpace($DetectionFileName)) {
                if (-not [string]::IsNullOrWhiteSpace($DetectionFileVersion)) {
                    $detectionClauses += New-CMDetectionClauseFile `
                        -Path $DetectionFilePath `
                        -FileName $DetectionFileName `
                        -Value `
                        -PropertyType Version `
                        -ExpressionOperator GreaterEquals `
                        -ExpectedValue $DetectionFileVersion
                } else {
                    $detectionClauses += New-CMDetectionClauseFile `
                        -Path $DetectionFilePath `
                        -FileName $DetectionFileName `
                        -Existence
                }
                Write-Log "File detection clause added: $DetectionFilePath\$DetectionFileName"
            }

            # Directory detection (optional — only added when both path and name are provided)
            if (-not [string]::IsNullOrWhiteSpace($DetectionDirPath) -and -not [string]::IsNullOrWhiteSpace($DetectionDirName)) {
                $detectionClauses += New-CMDetectionClauseDirectory `
                    -Path $DetectionDirPath `
                    -DirectoryName $DetectionDirName `
                    -Existence
                Write-Log "Directory detection clause added: $DetectionDirPath\$DetectionDirName"
            }

            # Windows Installer (MSI ProductCode) detection — most reliable for MSI-based apps.
            # New-CMDetectionClauseWindowsInstaller queries the Windows Installer product
            # registration database rather than the registry, so it survives repairs/patches.
            if (-not [string]::IsNullOrWhiteSpace($DetectionMsiProductCode)) {
                $msiDetectParams = @{ ProductCode = $DetectionMsiProductCode }
                if ($DetectionMsiVersionOp -and $DetectionMsiVersionOp -ne 'Exists') {
                    $msiDetectParams['ProductVersion']         = $DetectionMsiVersion
                    $msiDetectParams['ProductVersionOperator'] = $DetectionMsiVersionOp
                } else {
                    $msiDetectParams['ProductVersionOperator'] = 'Exists'
                }
                $detectionClauses += New-CMDetectionClauseWindowsInstaller @msiDetectParams
                Write-Log "Windows Installer detection clause added: ProductCode=$DetectionMsiProductCode (operator=$DetectionMsiVersionOp)"
            }

            Write-Log "Detection clauses built: $($detectionClauses.Count) clause(s)" -Level 'Success'

            #--- Add deployment type ---
            # Detect MSI: if the install command references a .msi file, use
            # Add-CMMsiDeploymentType (auto-detects via MSI ProductCode) instead
            # of Add-CMScriptDeploymentType.
            $msiMatch = [regex]::Match($InstallCommand, '[^\s"'']+\.msi', 'IgnoreCase')
            $isMsi    = $msiMatch.Success

            if ($isMsi) {
                $msiFileName  = [System.IO.Path]::GetFileName($msiMatch.Value)
                $msiFilePath  = Join-Path $ContentLocation $msiFileName
                $dtStepName   = "Add MSI deployment type"
            } else {
                $dtStepName   = "Add Script/EXE deployment type"
            }

            Invoke-Step -Name $dtStepName -Script {
                if (-not $WhatIf) {
                    $commonParams = @{
                        ApplicationName           = $AppName
                        DeploymentTypeName        = $DeploymentTypeName
                        InstallationBehaviorType  = 'InstallForSystem'
                        LogonRequirementType      = 'WhetherOrNotUserLoggedOn'
                        UserInteractionMode       = 'Hidden'
                        MaximumRuntimeMins        = $MaxRuntimeMins
                        RebootBehavior            = 'BasedOnExitCode'
                        SlowNetworkDeploymentMode = 'Download'
                    }

                    if ($isMsi) {
                        Write-Log "MSI detected ($msiFileName) — using Add-CMMsiDeploymentType (ProductCode auto-detection)"
                        Add-CMMsiDeploymentType @commonParams `
                            -ContentLocation $msiFilePath `
                            -ContentFallback `
                            -EnableBranchCache `
                            -ErrorAction Stop | Out-Null
                        Write-Log "MSI deployment type created (detection via ProductCode)" -Level 'Success'
                    } else {
                        $scriptDtParams = @{
                            ContentLocation    = $ContentLocation
                            InstallCommand     = $InstallCommand
                            ContentFallback    = $true
                            EnableBranchCache  = $true
                            AddDetectionClause = $detectionClauses
                        }
                        if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
                            $scriptDtParams['UninstallCommand'] = $UninstallCommand
                        }
                        Add-CMScriptDeploymentType @commonParams @scriptDtParams -ErrorAction Stop | Out-Null
                        Write-Log "Deployment type created with $($detectionClauses.Count) detection clause(s)" -Level 'Success'
                    }
                } else {
                    if ($isMsi) {
                        Write-Log "[WHATIF] Would add MSI deployment type '$DeploymentTypeName' using $msiFileName (ProductCode auto-detection)"
                    } else {
                        Write-Log "[WHATIF] Would add Script/EXE deployment type '$DeploymentTypeName' with $($detectionClauses.Count) detection clause(s)"
                    }
                }
            }

            #--- Set OS requirements ---
            Invoke-Step -Name "Add OS requirement (Windows 11 x64/ARM64)" -Script {
                if (-not $WhatIf) {
                    $osGC = Get-CMGlobalCondition -Name "Operating System" | Where-Object PlatformType -eq 1
                    if (-not $osGC) { throw "Operating System global condition not found" }

                    Set-CMDeploymentType -ApplicationName $AppName `
                        -DeploymentTypeName $DeploymentTypeName `
                        -ClearRequirements -ErrorAction Stop | Out-Null

                    $osRule = $osGC | New-CMRequirementRuleOperatingSystemValue `
                        -PlatformString @(
                            'Windows/All_x64_Windows_11_and_higher_Clients',
                            'Windows/All_ARM64_Windows_11_and_higher_Clients'
                        ) `
                        -RuleOperator OneOf

                    $setDtParams = @{
                        ApplicationName    = $AppName
                        DeploymentTypeName = $DeploymentTypeName
                        AddRequirement     = $osRule
                        ErrorAction        = 'Stop'
                    }
                    if ($isMsi) {
                        Set-CMMsiDeploymentType @setDtParams | Out-Null
                    } else {
                        Set-CMScriptDeploymentType @setDtParams | Out-Null
                    }

                    Write-Log "OS requirements configured: Windows 11 (x64 + ARM64)" -Level 'Success'
                } else {
                    Write-Log "[WHATIF] Would set OS requirement to Windows 11 x64/ARM64"
                }
            }

            #--- Distribute content ---
            Invoke-Step -Name "Distribute content to DP group '$DPGroupName'" -Script {
                $dpGroupObj = Get-CMDistributionPointGroup -Name $DPGroupName -ErrorAction SilentlyContinue
                if (-not $dpGroupObj) { throw "Distribution Point Group '$DPGroupName' not found." }
                if (-not $WhatIf) {
                    Start-CMContentDistribution -ApplicationName $AppName `
                        -DistributionPointGroupName $DPGroupName -ErrorAction Stop | Out-Null
                    Write-Log "Content distribution initiated to $($dpGroupObj.MemberCount) distribution point(s)" -Level 'Success'
                } else {
                    Write-Log "[WHATIF] Would distribute content to '$DPGroupName'"
                }
            }

            #--- Create install collection ---
            Invoke-Step -Name "Create device collection '$InstallCollectionName-UAT'" -Script {
                $limiter = Get-CMDeviceCollection -Name '__PACKAGING_ROOT_COLLECTION' -ErrorAction SilentlyContinue
                if (-not $limiter) { throw "Limiting collection '__PACKAGING_ROOT_COLLECTION' not found." }

                $collectionName = "$InstallCollectionName-UAT"
                $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                if (-not $existing) {
                    if (-not $WhatIf) {
                        New-CMDeviceCollection -Name $collectionName `
                            -LimitingCollectionId $limiter.CollectionID `
                            -Comment '~~UAT~~' -ErrorAction Stop | Out-Null
                        Write-Log "Collection created, waiting for provider replication..."
                        $timeout    = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
                        $retryCount = 0
                        do {
                            Start-Sleep -Seconds 3
                            $retryCount++
                            $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                            if ($existing) { Write-Log "Collection verified after $retryCount attempt(s)" -Level 'Success'; break }
                            if ([datetime]::UtcNow -gt $timeout) { throw "Collection creation timed out." }
                        } while (-not $existing)
                        $createdObjects.Collections += $collectionName
                    } else {
                        Write-Log "[WHATIF] Would create device collection '$collectionName'"
                    }
                } else {
                    Write-Log "Collection '$collectionName' already exists"
                }
            }

            #--- Create uninstall collection ---
            Invoke-Step -Name "Create device collection '$UninstallCollectionName-UAT'" -Script {
                $limiter = Get-CMDeviceCollection -Name '__PACKAGING_ROOT_COLLECTION' -ErrorAction SilentlyContinue
                if (-not $limiter) { throw "Limiting collection '__PACKAGING_ROOT_COLLECTION' not found." }

                $collectionName = "$UninstallCollectionName-UAT"
                $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                if (-not $existing) {
                    if (-not $WhatIf) {
                        New-CMDeviceCollection -Name $collectionName `
                            -LimitingCollectionId $limiter.CollectionID `
                            -Comment '~~UAT~~' -ErrorAction Stop | Out-Null
                        Write-Log "Collection created, waiting for provider replication..."
                        $timeout    = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
                        $retryCount = 0
                        do {
                            Start-Sleep -Seconds 3
                            $retryCount++
                            $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                            if ($existing) { Write-Log "Collection verified after $retryCount attempt(s)" -Level 'Success'; break }
                            if ([datetime]::UtcNow -gt $timeout) { throw "Collection creation timed out." }
                        } while (-not $existing)
                        $createdObjects.Collections += $collectionName
                    } else {
                        Write-Log "[WHATIF] Would create device collection '$collectionName'"
                    }
                } else {
                    Write-Log "Collection '$UninstallCollectionName' already exists"
                }
            }

            #--- Create install deployment ---
            Invoke-Step -Name "Deploy '$AppName' to '$InstallCollectionName' (Install / Required)" -Script {
                $retries = 0; $maxRetries = 10; $collection = $null
                do {
                    $collection = Get-CMDeviceCollection -Name $InstallCollectionName -ErrorAction SilentlyContinue
                    if ($collection) { break }
                    if ($retries -gt 0) { Write-Log "Waiting for collection replication... (attempt $retries/$maxRetries)"; Start-Sleep -Seconds 5 }
                    $retries++
                } while ($retries -le $maxRetries)

                if (-not $collection -and -not $WhatIf) { throw "Collection '$InstallCollectionName' not found after $maxRetries retries." }

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

            #--- Move to folders ---
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

            if (-not [string]::IsNullOrWhiteSpace($CollectionFolder)) {
                Invoke-Step -Name "Move collections to folder '$CollectionFolder'" -Script {
                    $fullPath = "${SiteCode}:\DeviceCollection\${CollectionFolder}"
                    foreach ($collName in @("$InstallCollectionName-UAT", "$UninstallCollectionName-UAT")) {
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
            Write-Log "========================================"  -Level 'Success'
            Write-Log "ALL STEPS COMPLETED SUCCESSFULLY"         -Level 'Success'
            Write-Log "Application: $AppName"                    -Level 'Success'
            Write-Log "========================================"  -Level 'Success'

        } catch {
            Write-Log "Deployment failed: $_" -Level 'Error'
            if (-not $NoRollback -and $createdObjects.Application) { Invoke-Rollback }
            throw
        }

    } catch {
        Write-Log "Script execution failed: $_" -Level 'Error'
    } finally {
        try {
            if ((Get-Location).Provider.Name -eq 'CMSite' -and $originalLocation) {
                Set-Location $originalLocation.Path -ErrorAction SilentlyContinue
            }
        } catch {}
        if ($LogFilePath) { Write-Log "Log file saved to: $LogFilePath" }
    }
}

#endregion

#region Import ConfigurationManager Module (before any runspace is created)

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

Import-Module $cmModulePath -ErrorAction SilentlyContinue

# The module may emit a WqlQueryException when it tries to auto-create CMSite PSDrives
# during import (WMI site discovery). That failure is non-fatal — we create the drive
# manually in the Connect step. Verify the CMSite PSProvider registered instead.
if (-not (Get-PSProvider -PSProvider 'CMSite' -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: ConfigurationManager module failed to load (CMSite provider not registered)." -ForegroundColor Red
    Write-Host "       Module path: $cmModulePath" -ForegroundColor Red
    exit 1
}
Write-Host "ConfigurationManager module imported." -ForegroundColor Green
Write-Host ""

#endregion

#region Launch HTTP Server in Background Runspace

$httpRunspace    = [runspacefactory]::CreateRunspace()
$httpRunspace.Open()
$httpPs          = [PowerShell]::Create()
$httpPs.Runspace = $httpRunspace
$httpPs.AddScript($HttpServerBlock).AddArgument($SharedState).AddArgument($Port) | Out-Null
$httpHandle      = $httpPs.BeginInvoke()

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
Write-Host "SCCM Deployment Web GUI Started"          -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Local:   http://localhost:$Port"        -ForegroundColor White
if ($primaryIP) { Write-Host "  Network: http://${primaryIP}:$Port" -ForegroundColor White }
foreach ($ip in ($localIPs | Select-Object -Skip 1)) { Write-Host "           http://${ip}:$Port" -ForegroundColor Gray }
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try { Start-Process "http://localhost:$Port" } catch {}

#endregion

#region Main Loop

try {
    while (-not $SharedState.StopServer) {

        if ($SharedState.DeployRequest -and -not $SharedState.IsDeploying) {

            $body                      = $SharedState.DeployRequest
            $SharedState.DeployRequest = $null
            $SharedState.IsDeploying   = $true

            try {
                $config = $body | ConvertFrom-Json

                $SharedState.LogMessages.Clear()
                [void]$SharedState.LogMessages.Add("=== DEPLOYMENT REQUEST ===")
                [void]$SharedState.LogMessages.Add("Timestamp:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
                [void]$SharedState.LogMessages.Add("Mode:        $(if ($config.WhatIf) { 'WhatIf' } else { 'Deploy' })")
                [void]$SharedState.LogMessages.Add("Application: $($config.AppName)")
                [void]$SharedState.LogMessages.Add("Site:        $($config.SiteCode) @ $($config.SiteServerFqdn)")
                [void]$SharedState.LogMessages.Add("========================")
                [void]$SharedState.LogMessages.Add("")

                $params = @{
                    AppName                          = $config.AppName
                    Description                      = $config.Description
                    SiteCode                         = $config.SiteCode
                    SiteServerFqdn                   = $config.SiteServerFqdn
                    ContentLocation                  = $config.ContentLocation
                    InstallCommand                   = $config.InstallCommand
                    UninstallCommand                 = $config.UninstallCommand
                    DeploymentTypeName               = $config.DeploymentTypeName
                    LimitingCollectionName           = $config.LimitingCollectionName
                    InstallCollectionName            = $config.InstallCollectionName
                    UninstallCollectionName          = $config.UninstallCollectionName
                    MaxRuntimeMins                   = $config.MaxRuntimeMins
                    CollectionCreationTimeoutMinutes = $config.CollectionCreationTimeoutMinutes
                    LogFilePath                      = $config.LogFilePath
                    Force                            = [bool]$config.Force
                    NoRollback                       = [bool]$config.NoRollback
                    VerboseLogging                   = [bool]$config.VerboseLogging
                    WhatIf                           = [bool]$config.WhatIf
                    # Detection method params
                    DetectionRegKeyName              = $config.DetectionRegKeyName
                    DetectionRegValueName            = $config.DetectionRegValueName
                    DetectionRegDataType             = $config.DetectionRegDataType
                    DetectionRegOperator             = $config.DetectionRegOperator
                    DetectionRegExpectedValue        = $config.DetectionRegExpectedValue
                    DetectionFilePath                = $config.DetectionFilePath
                    DetectionFileName                = $config.DetectionFileName
                    DetectionFileVersion             = $config.DetectionFileVersion
                    DetectionDirPath                 = $config.DetectionDirPath
                    DetectionDirName                 = $config.DetectionDirName
                    DetectionMsiProductCode          = $config.DetectionMsiProductCode
                    DetectionMsiVersionOp            = $config.DetectionMsiVersionOp
                    DetectionMsiVersion              = $config.DetectionMsiVersion
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
    $SharedState.StopServer = $true
    Start-Sleep -Milliseconds 700
    try { $httpPs.Stop()          } catch {}
    try { $httpPs.Dispose()       } catch {}
    try { $httpRunspace.Close()   } catch {}
    try { $httpRunspace.Dispose() } catch {}
    Write-Host "`nServer stopped." -ForegroundColor Yellow
}

#endregion
