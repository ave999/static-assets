#CAUTION: This email originated from outside of the organization. Do not click links or open attachments unless you recognize the sender and know the content is safe.

[CmdletBinding()]
param()

$Port = 80
$SiteCode = 'CM0'
$SiteServer = 'WAZEU2PRDDE051.corp.internal.citizensbank.com'
$ErrorActionPreference = 'Stop'

#region Shared State

$SharedState = [hashtable]::Synchronized(@{
    LogMessages   = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    IsDeploying   = $false
    DeployRequest = $null
    StopServer    = $false
    StatusMessage = ''
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
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',system-ui,sans-serif;background:#f5f7f5;color:#212529;min-height:100vh}
.container{max-width:1080px;margin:0 auto;padding:20px}
.header{text-align:center;padding:24px 0 16px}
.header h1{color:#00693E;font-size:1.75rem;font-weight:600}
.header p{color:#6c757d;margin-top:6px;font-size:.9rem}
/* ── Tabs ── */
.tabs{display:flex;border-bottom:2px solid #c8dfd3;margin-bottom:22px}
.tab-btn{padding:10px 26px;cursor:pointer;background:none;border:none;color:#6c757d;font-size:.9rem;border-bottom:3px solid transparent;margin-bottom:-2px;transition:color .15s,border-color .15s}
.tab-btn:hover{color:#333}
.tab-btn.active{color:#00693E;border-bottom-color:#00693E}
.tab-content{display:none}.tab-content.active{display:block}
/* ── Forms ── */
h2{font-size:1.1rem;font-weight:600;color:#333;margin-bottom:18px}
.form-group{margin-bottom:14px}
.form-row{display:grid;grid-template-columns:1fr 1fr;gap:14px}
@media(max-width:620px){.form-row{grid-template-columns:1fr}}
label{display:block;font-size:.8rem;color:#495057;margin-bottom:5px;font-weight:500}
label.required::after{content:' *';color:#dc3545}
input[type=text],input[type=number],textarea,select{
  width:100%;padding:8px 11px;background:#fff;border:1px solid #ced4da;
  border-radius:4px;color:#212529;font-size:.875rem;outline:none;transition:border-color .15s,box-shadow .15s}
input[type=text]:focus,input[type=number]:focus,textarea:focus,select:focus{border-color:#00693E;box-shadow:0 0 0 3px rgba(0,105,62,.12)}
input[readonly]{background:#f8f9fa;color:#6c757d;cursor:default}
textarea{resize:vertical;min-height:58px;font-family:inherit}
select option{background:#fff}
.help-text{font-size:.76rem;color:#6c757d;margin-top:4px}
.error-message{font-size:.76rem;color:#dc3545;margin-top:4px;display:none}
.has-error input,.has-error select,.has-error textarea{border-color:#dc3545 !important}
.has-error .error-message{display:block}
/* ── Fieldset ── */
fieldset{border:1px solid #c8dfd3;border-radius:6px;padding:14px 16px;margin-bottom:14px}
legend{padding:0 8px;color:#00693E;font-size:.8rem;font-weight:600;letter-spacing:.03em}
/* ── Detection sub-sections ── */
.det-section{border-left:2px solid #00693E;padding:10px 14px;margin-bottom:14px}
.det-section:last-child{margin-bottom:0}
.det-title{font-size:.75rem;font-weight:600;color:#00693E;letter-spacing:.05em;text-transform:uppercase;margin-bottom:12px}
/* ── Checkboxes ── */
.checkbox-group{display:flex;align-items:center;gap:10px;margin-bottom:12px}
.checkbox-group input[type=checkbox]{width:15px;height:15px;accent-color:#00693E;cursor:pointer;flex-shrink:0}
.checkbox-group label{margin:0;color:#333;font-size:.875rem;font-weight:400;cursor:pointer}
/* ── Validation summary ── */
.validation-summary{background:#fff5f5;border:1px solid #f5c2c7;border-radius:6px;padding:12px 16px;margin-bottom:16px;display:none}
.validation-summary.visible{display:block}
.validation-summary h3{color:#842029;font-size:.85rem;margin-bottom:8px}
.validation-summary ul{padding-left:18px}
.validation-summary li{color:#842029;font-size:.82rem;line-height:1.6}
/* ── Log ── */
.log-container{background:#fff;border:1px solid #c8dfd3;border-radius:6px;padding:12px 14px;font-family:'Consolas','Courier New',monospace;font-size:.8rem;height:420px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;color:#333}
.log-controls{display:flex;gap:8px;align-items:center;margin-bottom:10px;flex-wrap:wrap}
.log-ok{color:#00693E}.log-fail{color:#dc3545}.log-warn{color:#b45309}.log-step{color:#1565c0}.log-info{color:#495057}
/* ── Badge ── */
.status-badge{display:inline-block;padding:2px 10px;border-radius:10px;font-size:.72rem;font-weight:700;vertical-align:middle;margin-left:8px;text-transform:uppercase;letter-spacing:.05em}
.badge-ready{background:#d1fae5;color:#065f46}
.badge-running{background:#dbeafe;color:#1e40af}
.badge-done{background:#d1fae5;color:#065f46}
.badge-error{background:#fee2e2;color:#991b1b}
.badge-retry{background:#fef3c7;color:#92400e}
/* ── Buttons ── */
.actions{display:flex;gap:12px;margin-top:22px;padding-top:18px;border-top:1px solid #c8dfd3;flex-wrap:wrap}
.btn{padding:9px 22px;border-radius:5px;border:none;cursor:pointer;font-size:.875rem;font-weight:600;transition:filter .15s,opacity .15s}
.btn:hover:not(:disabled){filter:brightness(1.08)}
.btn:disabled{opacity:.38;cursor:not-allowed}
.btn-deploy{background:#00693E;color:#fff}
.btn-whatif{background:#1565c0;color:#fff}
.btn-sm{padding:5px 13px;font-size:.78rem;border-radius:4px;border:1px solid #ced4da;background:#fff;color:#495057;cursor:pointer;transition:border-color .15s,color .15s}
.btn-sm:hover{border-color:#00693E;color:#00693E}
.btn-sm.active{border-color:#00693E;color:#00693E;background:#f0faf4}
.btn-reset{background:#fff;color:#842029;padding:5px 13px;font-size:.78rem;border-radius:4px;border:1px solid #f5c2c7;cursor:pointer}
.btn-reset:hover{background:#fff5f5}
</style>
</head>
<body>
<div class="container">

<div class="header">
  <h1>SCCM Application Deployment Tool</h1>
  <p>Automated deployment with real-time monitoring</p>
</div>

<div class="tabs">
  <button class="tab-btn active" onclick="switchTab('config')">&#9881; Config</button>
  <button class="tab-btn"        onclick="switchTab('options')">&#9965; Options</button>
  <button class="tab-btn"        onclick="switchTab('log')"    >&#128196; Log</button>
</div>

<!-- ═══════════════════════ CONFIG TAB ═══════════════════════ -->
<div id="config" class="tab-content active">
<h2>Application Configuration</h2>

<div id="validationSummary" class="validation-summary">
  <h3>Please fix the following errors:</h3>
  <ul id="validationErrors"></ul>
</div>

<div class="form-row">
  <div class="form-group">
    <label class="required" for="appName">Application Name</label>
    <input type="text" id="appName" placeholder="e.g. Adobe Acrobat Reader DC 24.0">
    <div class="error-message" id="appName-error">Application Name is required</div>
    <div class="help-text">Unique name for the application in SCCM</div>
  </div>
  <div class="form-group">
    <label for="deploymentTypeName">Deployment Type Name</label>
    <input type="text" id="deploymentTypeName" placeholder="Defaults to &lt;AppName&gt;_Install">
  </div>
</div>

<div class="form-group">
  <label for="description">Description</label>
  <textarea id="description" rows="2" placeholder="Optional application description"></textarea>
</div>

<fieldset>
<legend>Content Settings</legend>
<div class="form-group">
  <label class="required" for="contentLocation">Content Location (UNC Path)</label>
  <input type="text" id="contentLocation" placeholder="\\server\share\AppName\1.0">
  <div class="error-message" id="contentLocation-error">Content Location is required and must be a UNC path (\\server\share\folder)</div>
  <div class="help-text">Network path to application source files</div>
</div>
<div class="form-row">
  <div class="form-group">
    <label class="required" for="installCmd">Install Command</label>
    <input type="text" id="installCmd" placeholder="setup.exe /S  or  install.msi">
    <div class="error-message" id="installCmd-error">Install Command is required</div>
  </div>
  <div class="form-group">
    <label for="uninstallCmd">Uninstall Command</label>
    <input type="text" id="uninstallCmd" placeholder="uninstall.exe /S  (optional)">
  </div>
</div>
<div class="form-group" style="max-width:220px">
  <label for="maxRuntime">Maximum Runtime (minutes)</label>
  <input type="number" id="maxRuntime" value="60" min="1" max="720">
</div>
</fieldset>

<fieldset>
<legend>Collections &amp; Distribution</legend>
<div class="form-group">
  <label class="required" for="limitingCollection">Limiting Collection</label>
  <input type="text" id="limitingCollection" placeholder="__PACKAGING_ROOT_COLLECTION">
  <div class="error-message" id="limitingCollection-error">Limiting Collection is required</div>
</div>
<div class="form-row">
  <div class="form-group">
    <label for="installCollection">Install Collection</label>
    <input type="text" id="installCollection" placeholder="Defaults to &lt;AppName&gt;">
  </div>
  <div class="form-group">
    <label for="uninstallCollection">Uninstall Collection</label>
    <input type="text" id="uninstallCollection" placeholder="Defaults to &lt;AppName&gt;_Uninstall">
  </div>
</div>
<div class="form-group">
  <label>Distribution Point Group</label>
  <input type="text" value="All Datacenter Distribution Points" readonly>
  <div class="help-text">Hardcoded — content always distributes to All Datacenter Distribution Points.</div>
</div>
</fieldset>

<fieldset>
<legend>Console Organization</legend>
<div class="form-row">
  <div class="form-group">
    <label for="appFolder">Application Folder Path</label>
    <input type="text" id="appFolder" placeholder="DSK\_STAGING">
  </div>
  <div class="form-group">
    <label for="collectionFolder">Collection Folder Path</label>
    <input type="text" id="collectionFolder" placeholder="DSK\Application Deployments\_STAGING">
  </div>
</div>
</fieldset>

<fieldset>
<legend>Detection Methods</legend>

<div class="form-group">
  <label for="detRegKeyName">Registry Uninstall Key Name</label>
  <input type="text" id="detRegKeyName" placeholder="Defaults to Application Name if blank">
  <div class="help-text">Key name under HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ (64-bit hive)</div>
</div>

<div class="det-section">
<div class="det-title">Registry Value Detection (optional)</div>
<div class="form-row">
  <div class="form-group">
    <label for="detRegValueName">Value Name</label>
    <input type="text" id="detRegValueName" placeholder="e.g. DisplayVersion">
  </div>
  <div class="form-group">
    <label for="detRegDataType">Data Type</label>
    <select id="detRegDataType">
      <option value="">— select —</option>
      <option value="String">String</option>
      <option value="Integer">Integer</option>
      <option value="Boolean">Boolean</option>
      <option value="DateTime">DateTime</option>
      <option value="FloatingPoint">FloatingPoint</option>
      <option value="Version">Version</option>
    </select>
  </div>
</div>
<div class="form-row">
  <div class="form-group">
    <label for="detRegOperator">Operator</label>
    <select id="detRegOperator">
      <option value="">— select —</option>
      <option value="IsEquals">IsEquals</option>
      <option value="NotEquals">NotEquals</option>
      <option value="GreaterThan">GreaterThan</option>
      <option value="GreaterEquals">GreaterEquals</option>
      <option value="LessThan">LessThan</option>
      <option value="LessEquals">LessEquals</option>
    </select>
  </div>
  <div class="form-group">
    <label for="detRegExpected">Expected Value</label>
    <input type="text" id="detRegExpected" placeholder="e.g. 24.0.0">
  </div>
</div>
<div class="help-text">Leave blank to check key existence only. All four fields are required for a value comparison.</div>
</div>

<div class="det-section">
<div class="det-title">File Detection (optional)</div>
<div class="form-row">
  <div class="form-group">
    <label for="detFilePath">File Path</label>
    <input type="text" id="detFilePath" placeholder="C:\Program Files\App">
  </div>
  <div class="form-group">
    <label for="detFileName">File Name</label>
    <input type="text" id="detFileName" placeholder="app.exe">
  </div>
</div>
<div class="form-group" style="max-width:280px">
  <label for="detFileVersion">Minimum Version <span style="font-weight:400;color:#555">(leave blank to check existence only)</span></label>
  <input type="text" id="detFileVersion" placeholder="e.g. 24.0.0.0">
</div>
</div>

<div class="det-section">
<div class="det-title">Directory Detection (optional)</div>
<div class="form-row">
  <div class="form-group">
    <label for="detDirPath">Directory Path</label>
    <input type="text" id="detDirPath" placeholder="C:\Program Files">
  </div>
  <div class="form-group">
    <label for="detDirName">Directory Name</label>
    <input type="text" id="detDirName" placeholder="AppName">
  </div>
</div>
</div>

<div class="det-section">
<div class="det-title">Windows Installer Detection (optional)</div>
<div class="form-row">
  <div class="form-group">
    <label for="detMsiCode">Product Code</label>
    <input type="text" id="detMsiCode" placeholder="{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}">
  </div>
  <div class="form-group">
    <label for="detMsiVersionOp">Version Operator</label>
    <select id="detMsiVersionOp">
      <option value="Exists">Exists</option>
      <option value="IsEquals">IsEquals</option>
      <option value="NotEquals">NotEquals</option>
      <option value="GreaterThan">GreaterThan</option>
      <option value="GreaterEquals">GreaterEquals</option>
      <option value="LessThan">LessThan</option>
      <option value="LessEquals">LessEquals</option>
    </select>
  </div>
</div>
<div class="form-group" style="max-width:280px">
  <label for="detMsiVersion">Product Version <span style="font-weight:400;color:#555">(required when operator is not Exists)</span></label>
  <input type="text" id="detMsiVersion" placeholder="e.g. 24.0.0.0">
</div>
<div class="help-text">Uses the Windows Installer (MSI) product registration database. Leave Product Code blank to skip.</div>
</div>

</fieldset>
</div><!-- /config -->

<!-- ═══════════════════════ OPTIONS TAB ═══════════════════════ -->
<div id="options" class="tab-content">
<h2>Deployment Options</h2>

<fieldset>
<legend>Logging</legend>
<div class="checkbox-group">
  <input type="checkbox" id="enableLogging" onchange="document.getElementById('logFilePath').disabled=!this.checked">
  <label for="enableLogging">Enable file logging</label>
</div>
<div class="form-group">
  <label for="logFilePath">Log File Path</label>
  <input type="text" id="logFilePath" placeholder="C:\Logs\SCCMDeploy.log" disabled>
  <div class="help-text">Full path to log file. Leave empty to skip file logging.</div>
</div>
</fieldset>

<fieldset>
<legend>Behaviour</legend>
<div class="checkbox-group">
  <input type="checkbox" id="forceMode">
  <label for="forceMode">Force mode (skip confirmation prompts)</label>
</div>
<div class="checkbox-group">
  <input type="checkbox" id="noRollback">
  <label for="noRollback">Disable automatic rollback on failure</label>
</div>
<div class="checkbox-group">
  <input type="checkbox" id="verboseLogging">
  <label for="verboseLogging">Enable verbose logging (recommended during testing)</label>
</div>
<div class="form-group" style="max-width:220px;margin-top:10px">
  <label for="collectionTimeout">Collection Creation Timeout (minutes)</label>
  <input type="number" id="collectionTimeout" value="5" min="1" max="30">
</div>
</fieldset>

<fieldset>
<legend>Site Connection</legend>
<div class="form-row">
  <div class="form-group">
    <label for="siteCode">Site Code</label>
    <input type="text" id="siteCode" value="CM0" placeholder="CM0">
  </div>
  <div class="form-group">
    <label for="siteServer">Site Server FQDN</label>
    <input type="text" id="siteServer" value="WAZEU2PRDDE051.corp.internal.citizensbank.com">
  </div>
</div>
</fieldset>
</div><!-- /options -->

<!-- ═══════════════════════ LOG TAB ═══════════════════════ -->
<div id="log" class="tab-content">
<h2>Execution Log <span id="statusBadge" class="status-badge badge-ready">Ready</span></h2>

<div class="log-controls">
  <button class="btn-sm" onclick="clearLog()">Clear</button>
  <button class="btn-sm active" id="btnAutoScroll" onclick="toggleAutoScroll()">Auto-scroll: ON</button>
  <button class="btn-reset" onclick="resetState()">Reset State</button>
</div>

<div id="logContainer" class="log-container">Ready to deploy. Configure your settings and click Deploy or WhatIf to begin.</div>
</div><!-- /log -->

<div class="actions">
  <button id="btnDeploy" class="btn btn-deploy" onclick="deploy(false)">&#9658; Deploy</button>
  <button id="btnWhatIf" class="btn btn-whatif" onclick="deploy(true)">&#128270; WhatIf</button>
</div>

</div><!-- /container -->
<script>
var _deploying=false,_autoScroll=true,_lastCount=0;

function switchTab(name){
  document.querySelectorAll('.tab-btn').forEach(function(b,i){
    b.classList.toggle('active',['config','options','log'][i]===name);
  });
  document.querySelectorAll('.tab-content').forEach(function(c){
    c.classList.toggle('active',c.id===name);
  });
}

function v(id){var e=document.getElementById(id);return e?e.value.trim():'';}
function cb(id){var e=document.getElementById(id);return e?e.checked:false;}
function n(id,def){var x=parseInt(v(id));return isNaN(x)?def:x;}

function validate(){
  var errors=[];
  var req=[
    {id:'appName',       label:'Application Name'},
    {id:'contentLocation',label:'Content Location'},
    {id:'installCmd',    label:'Install Command'},
    {id:'limitingCollection',label:'Limiting Collection'}
  ];
  req.forEach(function(f){
    var el=document.getElementById(f.id);
    var grp=el.closest('.form-group');
    if(!el.value.trim()){errors.push(f.label+' is required');grp.classList.add('has-error');}
    else grp.classList.remove('has-error');
  });
  var cl=document.getElementById('contentLocation');
  if(cl.value.trim()&&!cl.value.trim().startsWith('\\\\'))
    {errors.push('Content Location must be a UNC path (\\\\server\\share)');cl.closest('.form-group').classList.add('has-error');}
  var vs=document.getElementById('validationSummary');
  var vl=document.getElementById('validationErrors');
  if(errors.length){vl.innerHTML=errors.map(function(e){return'<li>'+e+'</li>';}).join('');vs.classList.add('visible');return false;}
  vs.classList.remove('visible');return true;
}

function buildConfig(whatIf){
  return{
    AppName:v('appName'),DeploymentTypeName:v('deploymentTypeName'),Description:v('description'),
    SiteCode:v('siteCode'),SiteServerFqdn:v('siteServer'),
    ContentLocation:v('contentLocation'),InstallCommand:v('installCmd'),UninstallCommand:v('uninstallCmd'),
    MaxRuntimeMins:n('maxRuntime',60),
    LimitingCollectionName:v('limitingCollection'),InstallCollectionName:v('installCollection'),UninstallCollectionName:v('uninstallCollection'),
    ApplicationFolder:v('appFolder'),CollectionFolder:v('collectionFolder'),
    DetectionRegKeyName:v('detRegKeyName'),
    DetectionRegValueName:v('detRegValueName'),DetectionRegDataType:v('detRegDataType'),
    DetectionRegOperator:v('detRegOperator'),DetectionRegExpectedValue:v('detRegExpected'),
    DetectionFilePath:v('detFilePath'),DetectionFileName:v('detFileName'),DetectionFileVersion:v('detFileVersion'),
    DetectionDirPath:v('detDirPath'),DetectionDirName:v('detDirName'),
    DetectionMsiProductCode:v('detMsiCode'),DetectionMsiVersionOp:v('detMsiVersionOp'),DetectionMsiVersion:v('detMsiVersion'),
    LogFilePath:cb('enableLogging')?v('logFilePath'):'',
    Force:cb('forceMode'),NoRollback:cb('noRollback'),VerboseLogging:cb('verboseLogging'),
    CollectionCreationTimeoutMinutes:n('collectionTimeout',5),
    WhatIf:whatIf
  };
}

function deploy(whatIf){
  if(!validate())return;
  if(_deploying)return;
  switchTab('log');
  setDeploying(true);
  fetch('/api/deploy',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(buildConfig(whatIf))})
    .then(function(r){return r.json();})
    .then(function(j){if(!j.success){appendLine('Failed to start: '+(j.error||'unknown error'),'fail');setDeploying(false);}})
    .catch(function(e){appendLine('Network error: '+e,'fail');setDeploying(false);});
}

function setDeploying(dep){
  _deploying=dep;
  var b=document.getElementById('statusBadge');
  if(dep){b.textContent='Running';b.className='status-badge badge-running';}
  else{b.textContent='Ready';b.className='status-badge badge-ready';}
  document.getElementById('btnDeploy').disabled=dep;
  document.getElementById('btnWhatIf').disabled=dep;
}

function appendLine(text,cls){
  var c=document.getElementById('logContainer');
  var sp=document.createElement('span');
  sp.className='log-'+(cls||'info');
  sp.textContent=text;
  c.appendChild(sp);c.appendChild(document.createTextNode('\n'));
  if(_autoScroll)c.scrollTop=c.scrollHeight;
}

function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function renderLogs(logs){
  var c=document.getElementById('logContainer');
  var html='';
  logs.forEach(function(line){
    if(!line){html+='<br>';return;}
    var cls='log-info';
    if(line.indexOf('[ OK ]')>=0)cls='log-ok';
    else if(line.indexOf('[FAIL]')>=0)cls='log-fail';
    else if(line.indexOf('[WARN]')>=0)cls='log-warn';
    else if(line.indexOf('[STEP]')>=0)cls='log-step';
    html+='<span class="'+cls+'">'+esc(line)+'</span>\n';
  });
  c.innerHTML=html;
  if(_autoScroll)c.scrollTop=c.scrollHeight;
}

function pollLogs(){
  fetch('/api/logs')
    .then(function(r){return r.json();})
    .then(function(j){
      if(j.logs&&j.logs.length!==_lastCount){_lastCount=j.logs.length;renderLogs(j.logs);}
      if(_deploying&&!j.isDeploying){
        setDeploying(false);
        var b=document.getElementById('statusBadge');
        var logs=j.logs||[];
        var last=logs.filter(function(l){return l;}).pop()||'';
        if(last.indexOf('[FAIL]')>=0){b.textContent='Failed';b.className='status-badge badge-error';}
        else{b.textContent='Done';b.className='status-badge badge-done';}
      }else if(!_deploying&&j.isDeploying){
        setDeploying(true);
      }
      if(_deploying&&j.statusMessage){
        var b=document.getElementById('statusBadge');
        b.textContent=j.statusMessage;b.className='status-badge badge-retry';
      }
    })
    .catch(function(){});
}

function clearLog(){
  fetch('/api/clear-log',{method:'POST'}).then(function(){_lastCount=0;}).catch(function(){});
}

function resetState(){
  if(!confirm('Reset deployment state? Use this only if the server is stuck after an interrupted run.'))return;
  fetch('/api/reset',{method:'POST'}).then(function(){setDeploying(false);_lastCount=0;}).catch(function(){});
}

function toggleAutoScroll(){
  _autoScroll=!_autoScroll;
  var b=document.getElementById('btnAutoScroll');
  b.textContent='Auto-scroll: '+(_autoScroll?'ON':'OFF');
  b.classList.toggle('active',_autoScroll);
}

setInterval(pollLogs,1000);
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
                            logs          = @($SharedState.LogMessages)
                            isDeploying   = [bool]$SharedState.IsDeploying
                            statusMessage = $SharedState.StatusMessage
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
                        $SharedState.IsDeploying  = $false
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
    $prefix = switch ($Level) {
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
    $AppName                         = $Config.AppName
    $Description                     = if ($Config.Description) { $Config.Description } else { "" }
    $SiteCode                        = $Config.SiteCode
    $SiteServerFqdn                  = $Config.SiteServerFqdn
    $ContentLocation                 = $Config.ContentLocation
    $InstallCommand                  = $Config.InstallCommand
    $UninstallCommand                = if ($Config.UninstallCommand) { $Config.UninstallCommand } else { "" }
    $DeploymentTypeName              = $Config.DeploymentTypeName
    $DPGroupName                     = 'All Datacenter Distribution Points'
    $LimitingCollectionName          = $Config.LimitingCollectionName
    $InstallCollectionName           = $Config.InstallCollectionName
    $UninstallCollectionName         = $Config.UninstallCollectionName
    $ApplicationFolder               = 'DSK\_STAGING'
    $CollectionFolder                = 'DSK\Application Deployments\_STAGING'
    $MaxRuntimeMins                  = if ($Config.MaxRuntimeMins) { $Config.MaxRuntimeMins } else { 60 }
    $CollectionCreationTimeoutMinutes = if ($Config.CollectionCreationTimeoutMinutes) { $Config.CollectionCreationTimeoutMinutes } else { 5 }
    $LogFilePath                     = $Config.LogFilePath
    $Force                           = [bool]$Config.Force
    $NoRollback                      = [bool]$Config.NoRollback
    $VerboseLogging                  = [bool]$Config.VerboseLogging
    $WhatIf                          = [bool]$Config.WhatIf

    # Detection method parameters
    $DetectionRegKeyName      = if ($Config.DetectionRegKeyName) { $Config.DetectionRegKeyName } else { $AppName }
    $DetectionRegValueName    = $Config.DetectionRegValueName
    $DetectionRegDataType     = $Config.DetectionRegDataType
    $DetectionRegOperator     = $Config.DetectionRegOperator
    $DetectionRegExpectedValue = $Config.DetectionRegExpectedValue
    $DetectionFilePath        = $Config.DetectionFilePath
    $DetectionFileName        = $Config.DetectionFileName
    $DetectionFileVersion     = $Config.DetectionFileVersion
    $DetectionDirPath         = $Config.DetectionDirPath
    $DetectionDirName         = $Config.DetectionDirName
    $DetectionMsiProductCode  = $Config.DetectionMsiProductCode
    $DetectionMsiVersionOp    = if ($Config.DetectionMsiVersionOp) { $Config.DetectionMsiVersionOp } else { 'Exists' }
    $DetectionMsiVersion      = $Config.DetectionMsiVersion

    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($DeploymentTypeName))      { $DeploymentTypeName      = "${AppName}_Install" }
    if ([string]::IsNullOrWhiteSpace($InstallCollectionName))   { $InstallCollectionName   = $AppName }
    if ([string]::IsNullOrWhiteSpace($UninstallCollectionName)) { $UninstallCollectionName = "${AppName}_Uninstall" }

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
        param([string]$Name, [scriptblock]$Script, [switch]$ContinueOnError, [int]$MaxRetries = 10)
        Write-Log -Message $Name -Level 'Step'
        $attempt = 0
        while ($true) {
            $attempt++
            try {
                if ($VerboseLogging) {
                    $verboseOutput = & $Script 4>&1 3>&1 2>&1
                    foreach ($line in $verboseOutput) {
                        if ($line) { Write-Log -Message "  [VERBOSE] $line" -Level 'Info' }
                    }
                } else {
                    $null = & $Script
                }
                $SharedState.StatusMessage = ''
                Write-Log -Message "$Name completed." -Level 'Success'
                return
            } catch {
                $ex = $_.Exception
                $isRetryable = ($ex -is [System.ArgumentNullException]) -or
                               ($ex -is [System.Management.ManagementException]) -or
                               ($ex.InnerException -is [System.Management.ManagementException])
                if ($isRetryable -and $attempt -lt $MaxRetries) {
                    $SharedState.StatusMessage = "Retrying ($attempt/$MaxRetries)..."
                    Write-Log -Message "SMS Provider connectivity error — retrying '$Name' ($attempt/$MaxRetries) in 2s..." -Level 'Warning'
                    Start-Sleep -Seconds 2
                } else {
                    $SharedState.StatusMessage = ''
                    Write-Log -Message "$Name failed." -Level 'Error'
                    Write-Log -Message "Error: $_" -Level 'Error'
                    if ($ex.InnerException) {
                        Write-Log -Message "InnerException: $($ex.InnerException)" -Level 'Error'
                    }
                    if (-not $ContinueOnError) { throw }
                    return
                }
            }
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
            $rbRemoved = $false
            try { Remove-CMApplication -Name $createdObjects.Application -Force -ErrorAction Stop; $rbRemoved = $true }
            catch [System.ArgumentNullException] {
                # CM SDK bug: verify via WMI whether the app is actually gone.
                $rbNameEsc = $createdObjects.Application -replace "'", "''"
                $rbWmiApp  = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" `
                    -Class SMS_Application `
                    -Filter "LocalizedDisplayName='$rbNameEsc' AND IsLatest=1" `
                    -ComputerName $SiteServerFqdn `
                    -ErrorAction SilentlyContinue
                if (-not $rbWmiApp) {
                    $rbRemoved = $true
                    Write-Log "Remove-CMApplication threw ArgumentNullException but application is gone from SMS Provider." -Level 'Warning'
                }
                # else: fall through to WMI direct deletion below
            }
            catch { Write-Log "Failed to remove application: $_" -Level 'Error' }

            if (-not $rbRemoved) {
                # Remove-CMApplication failed and app still exists — attempt direct WMI deletion.
                try {
                    $rbNameEsc2 = $createdObjects.Application -replace "'", "''"
                    $rbWmiApp2  = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" `
                        -Class SMS_Application `
                        -Filter "LocalizedDisplayName='$rbNameEsc2' AND IsLatest=1" `
                        -ComputerName $SiteServerFqdn `
                        -ErrorAction Stop
                    if ($rbWmiApp2) {
                        $rbWmiApp2.Delete() | Out-Null
                        Write-Log "Application removed via WMI direct deletion (fallback)." -Level 'Warning'
                    }
                } catch {
                    Write-Log "WMI fallback removal also failed — manually delete '$($createdObjects.Application)' from SCCM console: $_" -Level 'Error'
                }
            }
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
                $existing = $null
                try {
                    $existing = Get-CMApplication -Name $AppName -Fast -ErrorAction SilentlyContinue
                } catch {
                    Write-Log "Could not query existing application (non-fatal): $_" -Level 'Warning'
                }
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
                    try {
                        New-CMApplication -Name $AppName -Description $Description -ErrorAction Stop | Out-Null
                    } catch [System.ArgumentNullException] {
                        # Same CM SDK bug as Get-CMApplication above: the cmdlet may throw
                        # ArgumentNullException while processing its return object even after
                        # successfully writing to the SMS Provider. Verify via WMI directly
                        # (bypassing the module) before deciding to fail.
                        $nameEsc = $AppName -replace "'", "''"
                        $wmiApp  = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" `
                            -Class SMS_Application `
                            -Filter "LocalizedDisplayName='$nameEsc' AND IsLatest=1" `
                            -ComputerName $SiteServerFqdn `
                            -ErrorAction SilentlyContinue
                        if (-not $wmiApp) { throw }
                        Write-Log "New-CMApplication threw ArgumentNullException but application was created in SMS Provider — continuing." -Level 'Warning'
                    }
                    $createdObjects.Application = $AppName
                } else {
                    Write-Log "[WHATIF] Would create application '$AppName'"
                }
            }

            #--- Build detection clauses ---
            Write-Log "Building detection rules" -Level 'Step'

            # Registry detection — value comparison when all four fields are supplied,
            # key-existence only otherwise.
            $regHasValueDetection = (
                -not [string]::IsNullOrWhiteSpace($DetectionRegValueName)    -and
                -not [string]::IsNullOrWhiteSpace($DetectionRegDataType)     -and
                -not [string]::IsNullOrWhiteSpace($DetectionRegOperator)     -and
                -not [string]::IsNullOrWhiteSpace($DetectionRegExpectedValue)
            )

            if ($regHasValueDetection) {
                Write-Log "Registry value detection: $DetectionRegKeyName\$DetectionRegValueName $DetectionRegOperator '$DetectionRegExpectedValue' ($DetectionRegDataType)"
            } else {
                Write-Log "Registry key existence detection: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName"
            }
            if (-not [string]::IsNullOrWhiteSpace($DetectionFilePath) -and -not [string]::IsNullOrWhiteSpace($DetectionFileName)) {
                Write-Log "File detection clause added: $DetectionFilePath\$DetectionFileName"
            }
            if (-not [string]::IsNullOrWhiteSpace($DetectionDirPath) -and -not [string]::IsNullOrWhiteSpace($DetectionDirName)) {
                Write-Log "Directory detection clause added: $DetectionDirPath\$DetectionDirName"
            }
            if (-not [string]::IsNullOrWhiteSpace($DetectionMsiProductCode)) {
                Write-Log "Windows Installer detection clause added: ProductCode=$DetectionMsiProductCode (operator=$DetectionMsiVersionOp)"
            }

            # Clause objects in the ConfigMgr SDK carry a CMPSNoMask flag that is set
            # to True the moment they are consumed by any CM cmdlet. Passing the same
            # objects to a second cmdlet then throws "Invalid operation CMPSNoMask = True".
            # This scriptblock is invoked once per cmdlet call so each call receives its
            # own fresh set of objects.
            $BuildDetectionClauses = {
                $c = @()
                if ($regHasValueDetection) {
                    $c += New-CMDetectionClauseRegistryKeyValue `
                        -Hive LocalMachine -Is64Bit `
                        -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName" `
                        -ValueName $DetectionRegValueName -PropertyType $DetectionRegDataType `
                        -ExpressionOperator $DetectionRegOperator -Value -ExpectedValue $DetectionRegExpectedValue
                } else {
                    $c += New-CMDetectionClauseRegistryKey `
                        -Hive LocalMachine -Is64Bit `
                        -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$DetectionRegKeyName"
                }
                if (-not [string]::IsNullOrWhiteSpace($DetectionFilePath) -and -not [string]::IsNullOrWhiteSpace($DetectionFileName)) {
                    if (-not [string]::IsNullOrWhiteSpace($DetectionFileVersion)) {
                        $c += New-CMDetectionClauseFile -Path $DetectionFilePath -FileName $DetectionFileName `
                            -Value -PropertyType Version -ExpressionOperator GreaterEquals -ExpectedValue $DetectionFileVersion
                    } else {
                        $c += New-CMDetectionClauseFile -Path $DetectionFilePath -FileName $DetectionFileName -Existence
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($DetectionDirPath) -and -not [string]::IsNullOrWhiteSpace($DetectionDirName)) {
                    $c += New-CMDetectionClauseDirectory -Path $DetectionDirPath -DirectoryName $DetectionDirName -Existence
                }
                if (-not [string]::IsNullOrWhiteSpace($DetectionMsiProductCode)) {
                    $msiP = @{ ProductCode = $DetectionMsiProductCode }
                    if ($DetectionMsiVersionOp -and $DetectionMsiVersionOp -ne 'Exists') {
                        $msiP['ProductVersion']         = $DetectionMsiVersion
                        $msiP['ProductVersionOperator'] = $DetectionMsiVersionOp
                    } else {
                        $msiP['ProductVersionOperator'] = 'Exists'
                    }
                    $c += New-CMDetectionClauseWindowsInstaller @msiP
                }
                $c
            }

            $detectionClauses = & $BuildDetectionClauses
            Write-Log "Detection clauses built: $($detectionClauses.Count) clause(s)" -Level 'Success'

            #--- Add deployment type ---
            # Detect MSI: if the install command references a .msi file, use
            # Add-CMMsiDeploymentType (auto-detects via MSI ProductCode) instead
            # of Add-CMScriptDeploymentType.
            $msiMatch = [regex]::Match($InstallCommand, '[^\s"'']+\.msi', 'IgnoreCase')
            $isMsi    = $msiMatch.Success

            if ($isMsi) {
                $msiFileName = [System.IO.Path]::GetFileName($msiMatch.Value)
                $msiFilePath = Join-Path $ContentLocation $msiFileName
                $dtStepName  = "Add MSI deployment type"
            } else {
                $dtStepName = "Add Script/EXE deployment type"
            }

            Invoke-Step -Name $dtStepName -Script {
                if (-not $WhatIf) {
                    $commonParams = @{
                        ApplicationName          = $AppName
                        DeploymentTypeName       = $DeploymentTypeName
                        InstallationBehaviorType = 'InstallForSystem'
                        LogonRequirementType     = 'WhetherOrNotUserLoggedOn'
                        UserInteractionMode      = 'Hidden'
                        MaximumRuntimeMins       = $MaxRuntimeMins
                        RebootBehavior           = 'BasedOnExitCode'
                        SlowNetworkDeploymentMode = 'Download'
                    }

                    try {
                        if ($isMsi) {
                            Write-Log "MSI detected ($msiFileName) — using Add-CMMsiDeploymentType (ProductCode auto-detection)"
                            Add-CMMsiDeploymentType @commonParams `
                                -ContentLocation $msiFilePath `
                                -ContentFallback `
                                -EnableBranchCache `
                                -ErrorAction Stop | Out-Null
                            Write-Log "MSI deployment type created (detection via ProductCode)" -Level 'Success'
                        } else {
                            # Add-CMScriptDeploymentType both creates the deployment type AND
                            # persists the detection clauses in a single call. Passing
                            # AddDetectionClause here is required to switch the DT into
                            # clause-based detection mode (as opposed to Windows Installer mode).
                            # The clauses are built fresh via $BuildDetectionClauses so that the
                            # CMPSNoMask flag on each clause object has not yet been set.
                            # Do NOT follow this with a Set-CMScriptDeploymentType -AddDetectionClause
                            # call — that would append a second copy of every clause, producing
                            # duplicates.
                            $scriptDtParams = @{
                                ContentLocation   = $ContentLocation
                                InstallCommand    = $InstallCommand
                                ContentFallback   = $true
                                EnableBranchCache = $true
                                AddDetectionClause = (& $BuildDetectionClauses)
                            }
                            if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
                                $scriptDtParams['UninstallCommand'] = $UninstallCommand
                            }
                            Add-CMScriptDeploymentType @commonParams @scriptDtParams -ErrorAction Stop | Out-Null
                            Write-Log "Script/EXE deployment type created with $($detectionClauses.Count) detection clause(s)." -Level 'Success'
                        }
                    } catch [System.ArgumentNullException] {
                        # CM SDK bug: cmdlet may throw ArgumentNullException during result
                        # processing even after writing the DT to the SMS Provider.
                        # Verify via WMI directly before deciding to fail.
                        $dtNameEsc = $DeploymentTypeName -replace "'", "''"
                        $wmiDt = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" `
                            -Class SMS_DeploymentType `
                            -Filter "LocalizedDisplayName='$dtNameEsc' AND IsLatest=1" `
                            -ComputerName $SiteServerFqdn `
                            -ErrorAction SilentlyContinue
                        if (-not $wmiDt) { throw }
                        Write-Log "Add-CM*DeploymentType threw ArgumentNullException but deployment type was created in SMS Provider — continuing." -Level 'Warning'
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
                    try {
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
                    } catch [System.ArgumentNullException] {
                        # CM SDK bug: one or more cmdlets threw ArgumentNullException during
                        # result processing. Based on the consistent pattern seen throughout
                        # this deployment, writes to the SMS Provider complete before the
                        # exception fires. Log a warning and continue; verify requirements
                        # in the SCCM console if needed.
                        Write-Log "OS requirement step threw ArgumentNullException (CM SDK bug) — requirement may have been applied. Verify in SCCM console." -Level 'Warning'
                    }
                } else {
                    Write-Log "[WHATIF] Would set OS requirement to Windows 11 x64/ARM64"
                }
            }

            #--- Distribute content ---
            Invoke-Step -Name "Distribute content to DP group '$DPGroupName'" -Script {
                $dpGroupObj = $null
                try {
                    $dpGroupObj = Get-CMDistributionPointGroup -Name $DPGroupName -ErrorAction SilentlyContinue
                } catch [System.ArgumentNullException] {
                    # CM SDK bug: verify via WMI that the group exists before proceeding.
                    $dpNameEsc = $DPGroupName -replace "'", "''"
                    $dpGroupObj = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" `
                        -Class SMS_DistributionPointGroup `
                        -Filter "Name='$dpNameEsc'" `
                        -ComputerName $SiteServerFqdn `
                        -ErrorAction SilentlyContinue
                    if ($dpGroupObj) {
                        Write-Log "Get-CMDistributionPointGroup threw ArgumentNullException (CM SDK bug) — group verified via WMI." -Level 'Warning'
                    }
                }
                if (-not $dpGroupObj) { throw "Distribution Point Group '$DPGroupName' not found." }
                if (-not $WhatIf) {
                    try {
                        Start-CMContentDistribution -ApplicationName $AppName `
                            -DistributionPointGroupName $DPGroupName -ErrorAction Stop | Out-Null
                    } catch [System.ArgumentNullException] {
                        # CM SDK bug: cmdlet throws ArgumentNullException while processing its
                        # return value even though content distribution was initiated successfully.
                        Write-Log "Start-CMContentDistribution threw ArgumentNullException (CM SDK bug) — distribution was initiated. Verify in SCCM console." -Level 'Warning'
                    }
                    Write-Log "Content distribution initiated to DP group '$DPGroupName'" -Level 'Success'
                } else {
                    Write-Log "[WHATIF] Would distribute content to '$DPGroupName'"
                }
            }

            #--- Create install collection ---
            Invoke-Step -Name "Create device collection '$InstallCollectionName-UAT'" -Script {
                $limiter = $null
                try {
                    $limiter = Get-CMDeviceCollection -Name '__PACKAGING_ROOT_COLLECTION' -ErrorAction SilentlyContinue
                } catch [System.ArgumentNullException] {
                    $limiter = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                        -Filter "Name='__PACKAGING_ROOT_COLLECTION' AND CollectionType=2" `
                        -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                    if ($limiter) { Write-Log "Get-CMDeviceCollection threw ArgumentNullException — limiter verified via WMI." -Level 'Warning' }
                }
                if (-not $limiter) { throw "Limiting collection '__PACKAGING_ROOT_COLLECTION' not found." }

                $collectionName = "$InstallCollectionName-UAT"
                $existing = $null
                try {
                    $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                } catch [System.ArgumentNullException] {
                    # CM SDK bug: treat as not found and attempt creation
                }
                if (-not $existing) {
                    if (-not $WhatIf) {
                        try {
                            New-CMDeviceCollection -Name $collectionName `
                                -LimitingCollectionId $limiter.CollectionID `
                                -Comment '~~UAT~~' -ErrorAction Stop | Out-Null
                        } catch [System.ArgumentNullException] {
                            $collNameEsc = $collectionName -replace "'", "''"
                            $wmiColl = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                                -Filter "Name='$collNameEsc' AND CollectionType=2" `
                                -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                            if (-not $wmiColl) { throw }
                            Write-Log "New-CMDeviceCollection threw ArgumentNullException but collection was created in SMS Provider — continuing." -Level 'Warning'
                        }
                        Write-Log "Collection created, waiting for provider replication..."
                        $timeout    = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
                        $retryCount = 0
                        do {
                            Start-Sleep -Seconds 3
                            $retryCount++
                            $existing = $null
                            try {
                                $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                            } catch [System.ArgumentNullException] {
                                $collNameEsc2 = $collectionName -replace "'", "''"
                                $existing = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                                    -Filter "Name='$collNameEsc2' AND CollectionType=2" `
                                    -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                            }
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
                $limiter = $null
                try {
                    $limiter = Get-CMDeviceCollection -Name '__PACKAGING_ROOT_COLLECTION' -ErrorAction SilentlyContinue
                } catch [System.ArgumentNullException] {
                    $limiter = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                        -Filter "Name='__PACKAGING_ROOT_COLLECTION' AND CollectionType=2" `
                        -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                    if ($limiter) { Write-Log "Get-CMDeviceCollection threw ArgumentNullException — limiter verified via WMI." -Level 'Warning' }
                }
                if (-not $limiter) { throw "Limiting collection '__PACKAGING_ROOT_COLLECTION' not found." }

                $collectionName = "$UninstallCollectionName-UAT"
                $existing = $null
                try {
                    $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                } catch [System.ArgumentNullException] {
                    # CM SDK bug: treat as not found and attempt creation
                }
                if (-not $existing) {
                    if (-not $WhatIf) {
                        try {
                            New-CMDeviceCollection -Name $collectionName `
                                -LimitingCollectionId $limiter.CollectionID `
                                -Comment '~~UAT~~' -ErrorAction Stop | Out-Null
                        } catch [System.ArgumentNullException] {
                            $collNameEsc = $collectionName -replace "'", "''"
                            $wmiColl = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                                -Filter "Name='$collNameEsc' AND CollectionType=2" `
                                -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                            if (-not $wmiColl) { throw }
                            Write-Log "New-CMDeviceCollection threw ArgumentNullException but collection was created in SMS Provider — continuing." -Level 'Warning'
                        }
                        Write-Log "Collection created, waiting for provider replication..."
                        $timeout    = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
                        $retryCount = 0
                        do {
                            Start-Sleep -Seconds 3
                            $retryCount++
                            $existing = $null
                            try {
                                $existing = Get-CMDeviceCollection -Name $collectionName -ErrorAction SilentlyContinue
                            } catch [System.ArgumentNullException] {
                                $collNameEsc2 = $collectionName -replace "'", "''"
                                $existing = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                                    -Filter "Name='$collNameEsc2' AND CollectionType=2" `
                                    -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                            }
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

            #--- Create install deployment ---
            $installCollectionFull = "$InstallCollectionName-UAT"
            Invoke-Step -Name "Deploy '$AppName' to '$installCollectionFull' (Install / Required)" -Script {
                $retries = 0; $maxRetries = 10; $collection = $null
                do {
                    $collection = $null
                    try {
                        $collection = Get-CMDeviceCollection -Name $installCollectionFull -ErrorAction SilentlyContinue
                    } catch [System.ArgumentNullException] {
                        $collNameEsc = $installCollectionFull -replace "'", "''"
                        $collection = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Collection `
                            -Filter "Name='$collNameEsc' AND CollectionType=2" `
                            -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                    }
                    if ($collection) { break }
                    if ($retries -gt 0) { Write-Log "Waiting for collection replication... (attempt $retries/$maxRetries)"; Start-Sleep -Seconds 5 }
                    $retries++
                } while ($retries -le $maxRetries)

                if (-not $collection -and -not $WhatIf) { throw "Collection '$installCollectionFull' not found after $maxRetries retries." }

                if (-not $WhatIf) {
                    $deployment = $null
                    try {
                        $deployment = New-CMApplicationDeployment `
                            -ApplicationName  $AppName `
                            -CollectionId     $collection.CollectionID `
                            -DeployAction     Install `
                            -DeployPurpose    Required `
                            -UserNotification DisplaySoftwareCenterOnly `
                            -ErrorAction      Stop
                    } catch [System.ArgumentNullException] {
                        # CM SDK bug: verify the deployment was created in the SMS Provider.
                        $appNameEsc = $AppName -replace "'", "''"
                        $collId     = $collection.CollectionID
                        $wmiDeploy  = Get-WmiObject -Namespace "root\SMS\Site_$SiteCode" `
                            -Class SMS_ApplicationAssignment `
                            -Filter "ApplicationName='$appNameEsc' AND CollectionID='$collId'" `
                            -ComputerName $SiteServerFqdn -ErrorAction SilentlyContinue
                        if (-not $wmiDeploy) { throw }
                        Write-Log "New-CMApplicationDeployment threw ArgumentNullException (CM SDK bug) — deployment verified via WMI." -Level 'Warning'
                        $deployment = [PSCustomObject]@{ DeploymentID = $wmiDeploy.AssignmentUniqueID }
                    }
                    $createdObjects.Deployments += $deployment.DeploymentID
                    Write-Log "Deployment created (ID: $($deployment.DeploymentID))" -Level 'Success'
                } else {
                    Write-Log "[WHATIF] Would create Install/Required deployment to '$installCollectionFull'"
                }
            }

            #--- Move to folders ---
            if (-not [string]::IsNullOrWhiteSpace($ApplicationFolder)) {
                Invoke-Step -Name "Move application to folder '$ApplicationFolder'" -Script {
                    $fullPath = "${SiteCode}:\Application\${ApplicationFolder}"
                    if (-not $WhatIf) {
                        $app = $null
                        try {
                            $app = Get-CMApplication -Name $AppName -ErrorAction Stop
                        } catch [System.ArgumentNullException] {
                            Write-Log "Get-CMApplication threw ArgumentNullException (CM SDK bug) — skipping folder move for application. Verify in SCCM console." -Level 'Warning'
                            return
                        }
                        try {
                            Move-CMObject -FolderPath $fullPath -InputObject $app -ErrorAction Stop
                        } catch [System.ArgumentNullException] {
                            Write-Log "Move-CMObject threw ArgumentNullException (CM SDK bug) — folder move may have completed. Verify in SCCM console." -Level 'Warning'
                        }
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
                            $coll = $null
                            try {
                                $coll = Get-CMDeviceCollection -Name $collName -ErrorAction Stop
                            } catch [System.ArgumentNullException] {
                                Write-Log "Get-CMDeviceCollection threw ArgumentNullException (CM SDK bug) — skipping folder move for '$collName'. Verify in SCCM console." -Level 'Warning'
                                continue
                            }
                            try {
                                Move-CMObject -FolderPath $fullPath -InputObject $coll -ErrorAction Stop
                                Write-Log "Moved collection: $collName"
                            } catch [System.ArgumentNullException] {
                                Write-Log "Move-CMObject threw ArgumentNullException (CM SDK bug) — move may have completed for '$collName'. Verify in SCCM console." -Level 'Warning'
                            }
                        } else {
                            Write-Log "[WHATIF] Would move collection '$collName' to '$fullPath'"
                        }
                    }
                }
            }

            Write-Log ""
            Write-Log "========================================" -Level 'Success'
            Write-Log "ALL STEPS COMPLETED SUCCESSFULLY"        -Level 'Success'
            Write-Log "Application: $AppName"                   -Level 'Success'
            Write-Log "========================================" -Level 'Success'

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

$httpRunspace       = [runspacefactory]::CreateRunspace()
$httpRunspace.Open()
$httpPs             = [PowerShell]::Create()
$httpPs.Runspace    = $httpRunspace
$httpPs.AddScript($HttpServerBlock).AddArgument($SharedState).AddArgument($Port) | Out-Null
$httpHandle         = $httpPs.BeginInvoke()

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
Write-Host "Press Ctrl+C to stop the server"          -ForegroundColor Gray
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
                [void]$SharedState.LogMessages.Add("Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
                [void]$SharedState.LogMessages.Add("Mode: $(if ($config.WhatIf) { 'WhatIf' } else { 'Deploy' })")
                [void]$SharedState.LogMessages.Add("Application: $($config.AppName)")
                [void]$SharedState.LogMessages.Add("Site: $($config.SiteCode) @ $($config.SiteServerFqdn)")
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
    try { $httpPs.Stop()        } catch {}
    try { $httpPs.Dispose()     } catch {}
    try { $httpRunspace.Close() } catch {}
    try { $httpRunspace.Dispose() } catch {}
    Write-Host "`nServer stopped." -ForegroundColor Yellow
}

#endregion
