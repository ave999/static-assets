<#
.SYNOPSIS
    GUI front-end for SCCM Application Deployment script

.DESCRIPTION
    Provides a user-friendly Windows Forms interface for deploying SCCM applications
    with real-time progress tracking, validation, and log viewing.

.NOTES
    Author: Enhanced GUI wrapper for Deploy-SCCMApplication-Improved.ps1
    Version: 1.0
    Requires: Windows PowerShell, .NET Framework
#>

[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

#region Helper Functions

function Test-UNCPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return $Path -match '^\\\\[^\\]+\\[^\\]+'
}

function Write-LogOutput {
    param(
        [string]$Message,
        [System.Windows.Forms.RichTextBox]$LogBox
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logLine = "[$timestamp] $Message"

    $LogBox.AppendText("$logLine`r`n")
    $LogBox.SelectionStart = $LogBox.Text.Length
    $LogBox.ScrollToCaret()
    $LogBox.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-ScriptPath {
    return Split-Path -Parent $PSCommandPath
}

#endregion

#region Form Design

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SCCM Application Deployment Tool'
$form.Size = New-Object System.Drawing.Size(900, 750)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

# Create TabControl
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Size = New-Object System.Drawing.Size(860, 650)

#region Configuration Tab

$tabConfig = New-Object System.Windows.Forms.TabPage
$tabConfig.Text = 'Configuration'
$tabConfig.Padding = New-Object System.Windows.Forms.Padding(10)

$yPos = 15

# Application Name
$lblAppName = New-Object System.Windows.Forms.Label
$lblAppName.Text = 'Application Name:'
$lblAppName.Location = New-Object System.Drawing.Point(20, $yPos)
$lblAppName.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblAppName)

$txtAppName = New-Object System.Windows.Forms.TextBox
$txtAppName.Location = New-Object System.Drawing.Point(180, $yPos)
$txtAppName.Size = New-Object System.Drawing.Size(400, 20)
$txtAppName.Text = 'MSCPPROJECTSTD_2024_00S00_P'
$tabConfig.Controls.Add($txtAppName)

$yPos += 35

# Description
$lblDescription = New-Object System.Windows.Forms.Label
$lblDescription.Text = 'Description:'
$lblDescription.Location = New-Object System.Drawing.Point(20, $yPos)
$lblDescription.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblDescription)

$txtDescription = New-Object System.Windows.Forms.TextBox
$txtDescription.Location = New-Object System.Drawing.Point(180, $yPos)
$txtDescription.Size = New-Object System.Drawing.Size(640, 20)
$txtDescription.Text = 'Custom application - scripted install'
$tabConfig.Controls.Add($txtDescription)

$yPos += 35

# Site Code
$lblSiteCode = New-Object System.Windows.Forms.Label
$lblSiteCode.Text = 'Site Code:'
$lblSiteCode.Location = New-Object System.Drawing.Point(20, $yPos)
$lblSiteCode.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblSiteCode)

$txtSiteCode = New-Object System.Windows.Forms.TextBox
$txtSiteCode.Location = New-Object System.Drawing.Point(180, $yPos)
$txtSiteCode.Size = New-Object System.Drawing.Size(100, 20)
$txtSiteCode.Text = '365'
$tabConfig.Controls.Add($txtSiteCode)

# Site Server FQDN
$lblSiteServer = New-Object System.Windows.Forms.Label
$lblSiteServer.Text = 'Site Server FQDN:'
$lblSiteServer.Location = New-Object System.Drawing.Point(320, $yPos)
$lblSiteServer.Size = New-Object System.Drawing.Size(120, 20)
$tabConfig.Controls.Add($lblSiteServer)

$txtSiteServer = New-Object System.Windows.Forms.TextBox
$txtSiteServer.Location = New-Object System.Drawing.Point(450, $yPos)
$txtSiteServer.Size = New-Object System.Drawing.Size(370, 20)
$txtSiteServer.Text = 'eusdevptp3.namdev.nsrootdev.net'
$tabConfig.Controls.Add($txtSiteServer)

$yPos += 35

# Content Location with Browse button
$lblContentLocation = New-Object System.Windows.Forms.Label
$lblContentLocation.Text = 'Content Location (UNC):'
$lblContentLocation.Location = New-Object System.Drawing.Point(20, $yPos)
$lblContentLocation.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblContentLocation)

$txtContentLocation = New-Object System.Windows.Forms.TextBox
$txtContentLocation.Location = New-Object System.Drawing.Point(180, $yPos)
$txtContentLocation.Size = New-Object System.Drawing.Size(550, 20)
$txtContentLocation.Text = '\\eusdevptp3\SCCMSource\Applications\Defender'
$tabConfig.Controls.Add($txtContentLocation)

$btnBrowseContent = New-Object System.Windows.Forms.Button
$btnBrowseContent.Text = '...'
$btnBrowseContent.Location = New-Object System.Drawing.Point(740, $yPos - 2)
$btnBrowseContent.Size = New-Object System.Drawing.Size(80, 24)
$btnBrowseContent.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = 'Select content location folder'
    $folderBrowser.ShowNewFolderButton = $false

    if ($folderBrowser.ShowDialog() -eq 'OK') {
        $txtContentLocation.Text = $folderBrowser.SelectedPath
    }
})
$tabConfig.Controls.Add($btnBrowseContent)

$yPos += 35

# Install Command
$lblInstallCmd = New-Object System.Windows.Forms.Label
$lblInstallCmd.Text = 'Install Command:'
$lblInstallCmd.Location = New-Object System.Drawing.Point(20, $yPos)
$lblInstallCmd.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblInstallCmd)

$txtInstallCmd = New-Object System.Windows.Forms.TextBox
$txtInstallCmd.Location = New-Object System.Drawing.Point(180, $yPos)
$txtInstallCmd.Size = New-Object System.Drawing.Size(640, 20)
$txtInstallCmd.Text = 'InstallProjectSTD2024.cmd'
$tabConfig.Controls.Add($txtInstallCmd)

$yPos += 35

# Uninstall Command
$lblUninstallCmd = New-Object System.Windows.Forms.Label
$lblUninstallCmd.Text = 'Uninstall Command:'
$lblUninstallCmd.Location = New-Object System.Drawing.Point(20, $yPos)
$lblUninstallCmd.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblUninstallCmd)

$txtUninstallCmd = New-Object System.Windows.Forms.TextBox
$txtUninstallCmd.Location = New-Object System.Drawing.Point(180, $yPos)
$txtUninstallCmd.Size = New-Object System.Drawing.Size(640, 20)
$txtUninstallCmd.Text = 'RemoveProjectSTD2024.cmd'
$tabConfig.Controls.Add($txtUninstallCmd)

$yPos += 35

# Deployment Type Name
$lblDeployTypeName = New-Object System.Windows.Forms.Label
$lblDeployTypeName.Text = 'Deployment Type Name:'
$lblDeployTypeName.Location = New-Object System.Drawing.Point(20, $yPos)
$lblDeployTypeName.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblDeployTypeName)

$txtDeployTypeName = New-Object System.Windows.Forms.TextBox
$txtDeployTypeName.Location = New-Object System.Drawing.Point(180, $yPos)
$txtDeployTypeName.Size = New-Object System.Drawing.Size(400, 20)
$txtDeployTypeName.Text = 'MSCPPROJECTSTD_2024_00S00_DEPLOY01'
$tabConfig.Controls.Add($txtDeployTypeName)

$yPos += 35

# Max Runtime
$lblMaxRuntime = New-Object System.Windows.Forms.Label
$lblMaxRuntime.Text = 'Max Runtime (minutes):'
$lblMaxRuntime.Location = New-Object System.Drawing.Point(20, $yPos)
$lblMaxRuntime.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblMaxRuntime)

$numMaxRuntime = New-Object System.Windows.Forms.NumericUpDown
$numMaxRuntime.Location = New-Object System.Drawing.Point(180, $yPos)
$numMaxRuntime.Size = New-Object System.Drawing.Size(100, 20)
$numMaxRuntime.Minimum = 1
$numMaxRuntime.Maximum = 720
$numMaxRuntime.Value = 60
$tabConfig.Controls.Add($numMaxRuntime)

$yPos += 45

# Group box for Collections
$grpCollections = New-Object System.Windows.Forms.GroupBox
$grpCollections.Text = 'Collections'
$grpCollections.Location = New-Object System.Drawing.Point(20, $yPos)
$grpCollections.Size = New-Object System.Drawing.Size(800, 120)
$tabConfig.Controls.Add($grpCollections)

# Limiting Collection
$lblLimitingCollection = New-Object System.Windows.Forms.Label
$lblLimitingCollection.Text = 'Limiting Collection:'
$lblLimitingCollection.Location = New-Object System.Drawing.Point(15, 25)
$lblLimitingCollection.Size = New-Object System.Drawing.Size(150, 20)
$grpCollections.Controls.Add($lblLimitingCollection)

$txtLimitingCollection = New-Object System.Windows.Forms.TextBox
$txtLimitingCollection.Location = New-Object System.Drawing.Point(170, 25)
$txtLimitingCollection.Size = New-Object System.Drawing.Size(600, 20)
$txtLimitingCollection.Text = 'All Desktop and Server Clients'
$grpCollections.Controls.Add($txtLimitingCollection)

# Install Collection
$lblInstallCollection = New-Object System.Windows.Forms.Label
$lblInstallCollection.Text = 'Install Collection:'
$lblInstallCollection.Location = New-Object System.Drawing.Point(15, 55)
$lblInstallCollection.Size = New-Object System.Drawing.Size(150, 20)
$grpCollections.Controls.Add($lblInstallCollection)

$txtInstallCollection = New-Object System.Windows.Forms.TextBox
$txtInstallCollection.Location = New-Object System.Drawing.Point(170, 55)
$txtInstallCollection.Size = New-Object System.Drawing.Size(600, 20)
$txtInstallCollection.PlaceholderText = '(defaults to Application Name)'
$grpCollections.Controls.Add($txtInstallCollection)

# Uninstall Collection
$lblUninstallCollection = New-Object System.Windows.Forms.Label
$lblUninstallCollection.Text = 'Uninstall Collection:'
$lblUninstallCollection.Location = New-Object System.Drawing.Point(15, 85)
$lblUninstallCollection.Size = New-Object System.Drawing.Size(150, 20)
$grpCollections.Controls.Add($lblUninstallCollection)

$txtUninstallCollection = New-Object System.Windows.Forms.TextBox
$txtUninstallCollection.Location = New-Object System.Drawing.Point(170, 85)
$txtUninstallCollection.Size = New-Object System.Drawing.Size(600, 20)
$txtUninstallCollection.PlaceholderText = '(defaults to Application Name + _Uninstall)'
$grpCollections.Controls.Add($txtUninstallCollection)

$yPos += 130

# DP Group Name
$lblDPGroup = New-Object System.Windows.Forms.Label
$lblDPGroup.Text = 'Distribution Point Group:'
$lblDPGroup.Location = New-Object System.Drawing.Point(20, $yPos)
$lblDPGroup.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblDPGroup)

$txtDPGroup = New-Object System.Windows.Forms.TextBox
$txtDPGroup.Location = New-Object System.Drawing.Point(180, $yPos)
$txtDPGroup.Size = New-Object System.Drawing.Size(400, 20)
$txtDPGroup.Text = 'All Distribution Points'
$tabConfig.Controls.Add($txtDPGroup)

$yPos += 35

# Application Folder
$lblAppFolder = New-Object System.Windows.Forms.Label
$lblAppFolder.Text = 'Application Folder Path:'
$lblAppFolder.Location = New-Object System.Drawing.Point(20, $yPos)
$lblAppFolder.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblAppFolder)

$txtAppFolder = New-Object System.Windows.Forms.TextBox
$txtAppFolder.Location = New-Object System.Drawing.Point(180, $yPos)
$txtAppFolder.Size = New-Object System.Drawing.Size(640, 20)
$txtAppFolder.Text = 'Desktops\3. PROD'
$tabConfig.Controls.Add($txtAppFolder)

$yPos += 35

# Collection Folder
$lblCollectionFolder = New-Object System.Windows.Forms.Label
$lblCollectionFolder.Text = 'Collection Folder Path:'
$lblCollectionFolder.Location = New-Object System.Drawing.Point(20, $yPos)
$lblCollectionFolder.Size = New-Object System.Drawing.Size(150, 20)
$tabConfig.Controls.Add($lblCollectionFolder)

$txtCollectionFolder = New-Object System.Windows.Forms.TextBox
$txtCollectionFolder.Location = New-Object System.Drawing.Point(180, $yPos)
$txtCollectionFolder.Size = New-Object System.Drawing.Size(640, 20)
$txtCollectionFolder.Text = 'Desktops\Applications\3. PROD'
$tabConfig.Controls.Add($txtCollectionFolder)

#endregion

#region Options Tab

$tabOptions = New-Object System.Windows.Forms.TabPage
$tabOptions.Text = 'Options'
$tabOptions.Padding = New-Object System.Windows.Forms.Padding(10)

$yPos = 20

# Enable Logging
$chkEnableLogging = New-Object System.Windows.Forms.CheckBox
$chkEnableLogging.Text = 'Enable file logging'
$chkEnableLogging.Location = New-Object System.Drawing.Point(20, $yPos)
$chkEnableLogging.Size = New-Object System.Drawing.Size(150, 20)
$chkEnableLogging.Checked = $true
$tabOptions.Controls.Add($chkEnableLogging)

$yPos += 30

# Log File Path
$lblLogPath = New-Object System.Windows.Forms.Label
$lblLogPath.Text = 'Log File Path:'
$lblLogPath.Location = New-Object System.Drawing.Point(40, $yPos)
$lblLogPath.Size = New-Object System.Drawing.Size(100, 20)
$tabOptions.Controls.Add($lblLogPath)

$txtLogPath = New-Object System.Windows.Forms.TextBox
$txtLogPath.Location = New-Object System.Drawing.Point(150, $yPos)
$txtLogPath.Size = New-Object System.Drawing.Size(550, 20)
$txtLogPath.Text = "$env:TEMP\SCCM-Deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$tabOptions.Controls.Add($txtLogPath)

$btnBrowseLog = New-Object System.Windows.Forms.Button
$btnBrowseLog.Text = '...'
$btnBrowseLog.Location = New-Object System.Drawing.Point(710, $yPos - 2)
$btnBrowseLog.Size = New-Object System.Drawing.Size(80, 24)
$btnBrowseLog.Add_Click({
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = 'Log Files (*.log)|*.log|Text Files (*.txt)|*.txt|All Files (*.*)|*.*'
    $saveDialog.DefaultExt = 'log'
    $saveDialog.FileName = "SCCM-Deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    if ($saveDialog.ShowDialog() -eq 'OK') {
        $txtLogPath.Text = $saveDialog.FileName
    }
})
$tabOptions.Controls.Add($btnBrowseLog)

# Bind enable/disable log path based on checkbox
$chkEnableLogging.Add_CheckedChanged({
    $txtLogPath.Enabled = $chkEnableLogging.Checked
    $btnBrowseLog.Enabled = $chkEnableLogging.Checked
})

$yPos += 40

# Force mode
$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = 'Force mode (skip confirmation prompts)'
$chkForce.Location = New-Object System.Drawing.Point(20, $yPos)
$chkForce.Size = New-Object System.Drawing.Size(300, 20)
$chkForce.Checked = $false
$tabOptions.Controls.Add($chkForce)

$yPos += 30

# No Rollback
$chkNoRollback = New-Object System.Windows.Forms.CheckBox
$chkNoRollback.Text = 'Disable automatic rollback on failure'
$chkNoRollback.Location = New-Object System.Drawing.Point(20, $yPos)
$chkNoRollback.Size = New-Object System.Drawing.Size(300, 20)
$chkNoRollback.Checked = $false
$tabOptions.Controls.Add($chkNoRollback)

$yPos += 30

# Collection Creation Timeout
$lblCollectionTimeout = New-Object System.Windows.Forms.Label
$lblCollectionTimeout.Text = 'Collection Creation Timeout (minutes):'
$lblCollectionTimeout.Location = New-Object System.Drawing.Point(20, $yPos)
$lblCollectionTimeout.Size = New-Object System.Drawing.Size(250, 20)
$tabOptions.Controls.Add($lblCollectionTimeout)

$numCollectionTimeout = New-Object System.Windows.Forms.NumericUpDown
$numCollectionTimeout.Location = New-Object System.Drawing.Point(280, $yPos)
$numCollectionTimeout.Size = New-Object System.Drawing.Size(100, 20)
$numCollectionTimeout.Minimum = 1
$numCollectionTimeout.Maximum = 30
$numCollectionTimeout.Value = 5
$tabOptions.Controls.Add($numCollectionTimeout)

$yPos += 50

# Info text
$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = @"
Script Location: Deploy-SCCMApplication-Improved.ps1
This GUI requires the improved deployment script to be in the same folder.

WhatIf Mode: Tests the deployment without making any changes.
Deploy Mode: Executes the actual deployment to SCCM.
"@
$lblInfo.Location = New-Object System.Drawing.Point(20, $yPos)
$lblInfo.Size = New-Object System.Drawing.Size(800, 80)
$lblInfo.ForeColor = [System.Drawing.Color]::DarkBlue
$tabOptions.Controls.Add($lblInfo)

#endregion

#region Log Output Tab

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = 'Execution Log'
$tabLog.Padding = New-Object System.Windows.Forms.Padding(10)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location = New-Object System.Drawing.Point(10, 10)
$rtbLog.Size = New-Object System.Drawing.Size(830, 560)
$rtbLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$rtbLog.ReadOnly = $true
$rtbLog.BackColor = [System.Drawing.Color]::Black
$rtbLog.ForeColor = [System.Drawing.Color]::LightGreen
$rtbLog.Text = "Ready to deploy...`r`n`r`nConfigure your deployment settings in the Configuration tab, then click Deploy or WhatIf.`r`n"
$tabLog.Controls.Add($rtbLog)

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = 'Clear Log'
$btnClearLog.Location = New-Object System.Drawing.Point(10, 580)
$btnClearLog.Size = New-Object System.Drawing.Size(100, 30)
$btnClearLog.Add_Click({
    $rtbLog.Clear()
    Write-LogOutput -Message "Log cleared" -LogBox $rtbLog
})
$tabLog.Controls.Add($btnClearLog)

$btnSaveLog = New-Object System.Windows.Forms.Button
$btnSaveLog.Text = 'Save Log'
$btnSaveLog.Location = New-Object System.Drawing.Point(120, 580)
$btnSaveLog.Size = New-Object System.Drawing.Size(100, 30)
$btnSaveLog.Add_Click({
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = 'Log Files (*.log)|*.log|Text Files (*.txt)|*.txt'
    $saveDialog.DefaultExt = 'log'
    $saveDialog.FileName = "GUI-Session-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    if ($saveDialog.ShowDialog() -eq 'OK') {
        $rtbLog.Text | Out-File -FilePath $saveDialog.FileName -Encoding UTF8
        [System.Windows.Forms.MessageBox]::Show("Log saved to:`n$($saveDialog.FileName)", "Success", 'OK', 'Information')
    }
})
$tabLog.Controls.Add($btnSaveLog)

#endregion

# Add tabs to TabControl
$tabControl.Controls.Add($tabConfig)
$tabControl.Controls.Add($tabOptions)
$tabControl.Controls.Add($tabLog)
$form.Controls.Add($tabControl)

#region Action Buttons

$btnWhatIf = New-Object System.Windows.Forms.Button
$btnWhatIf.Text = 'WhatIf (Test Run)'
$btnWhatIf.Location = New-Object System.Drawing.Point(430, 670)
$btnWhatIf.Size = New-Object System.Drawing.Size(140, 35)
$btnWhatIf.BackColor = [System.Drawing.Color]::LightBlue
$form.Controls.Add($btnWhatIf)

$btnDeploy = New-Object System.Windows.Forms.Button
$btnDeploy.Text = 'Deploy'
$btnDeploy.Location = New-Object System.Drawing.Point(580, 670)
$btnDeploy.Size = New-Object System.Drawing.Size(140, 35)
$btnDeploy.BackColor = [System.Drawing.Color]::LightGreen
$form.Controls.Add($btnDeploy)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Close'
$btnCancel.Location = New-Object System.Drawing.Point(730, 670)
$btnCancel.Size = New-Object System.Drawing.Size(140, 35)
$btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($btnCancel)

$form.CancelButton = $btnCancel

#endregion

#region Event Handlers

function Invoke-Validation {
    $errors = @()

    if ([string]::IsNullOrWhiteSpace($txtAppName.Text)) {
        $errors += "Application Name is required"
    }

    if ([string]::IsNullOrWhiteSpace($txtSiteCode.Text)) {
        $errors += "Site Code is required"
    }

    if ([string]::IsNullOrWhiteSpace($txtSiteServer.Text)) {
        $errors += "Site Server FQDN is required"
    }

    if ([string]::IsNullOrWhiteSpace($txtContentLocation.Text)) {
        $errors += "Content Location is required"
    }
    elseif (-not (Test-UNCPath $txtContentLocation.Text)) {
        $errors += "Content Location must be a valid UNC path (e.g., \\server\share\folder)"
    }

    if ([string]::IsNullOrWhiteSpace($txtInstallCmd.Text)) {
        $errors += "Install Command is required"
    }

    if ([string]::IsNullOrWhiteSpace($txtDPGroup.Text)) {
        $errors += "Distribution Point Group is required"
    }

    if ([string]::IsNullOrWhiteSpace($txtLimitingCollection.Text)) {
        $errors += "Limiting Collection is required"
    }

    if ($errors.Count -gt 0) {
        $errorMessage = "Please fix the following errors:`r`n`r`n" + ($errors -join "`r`n")
        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Validation Error", 'OK', 'Error')
        return $false
    }

    return $true
}

function Invoke-Deployment {
    param([bool]$WhatIfMode)

    # Validate inputs
    if (-not (Invoke-Validation)) {
        return
    }

    # Check if script exists
    $scriptPath = Join-Path (Get-ScriptPath) "Deploy-SCCMApplication-Improved.ps1"

    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not find Deploy-SCCMApplication-Improved.ps1 in the same folder as this GUI.`r`n`r`nScript Path: $scriptPath",
            "Script Not Found",
            'OK',
            'Error'
        )
        return
    }

    # Switch to log tab
    $tabControl.SelectedTab = $tabLog

    # Clear log if starting fresh
    if ($rtbLog.Text -notmatch "Starting deployment") {
        $rtbLog.Clear()
    }

    Write-LogOutput -Message "========================================" -LogBox $rtbLog
    if ($WhatIfMode) {
        Write-LogOutput -Message "WHATIF MODE - No changes will be made" -LogBox $rtbLog
    }
    else {
        Write-LogOutput -Message "DEPLOYMENT MODE - Changes will be applied" -LogBox $rtbLog
    }
    Write-LogOutput -Message "========================================" -LogBox $rtbLog
    Write-LogOutput -Message "Application: $($txtAppName.Text)" -LogBox $rtbLog
    Write-LogOutput -Message "Site: $($txtSiteCode.Text) ($($txtSiteServer.Text))" -LogBox $rtbLog
    Write-LogOutput -Message "========================================" -LogBox $rtbLog
    Write-LogOutput -Message "" -LogBox $rtbLog

    # Disable buttons during execution
    $btnWhatIf.Enabled = $false
    $btnDeploy.Enabled = $false

    try {
        # Build parameters
        $params = @{
            AppName                           = $txtAppName.Text
            Description                       = $txtDescription.Text
            SiteCode                          = $txtSiteCode.Text
            SiteServerFqdn                    = $txtSiteServer.Text
            ContentLocation                   = $txtContentLocation.Text
            InstallCommand                    = $txtInstallCmd.Text
            UninstallCommand                  = $txtUninstallCmd.Text
            DeploymentTypeName                = $txtDeployTypeName.Text
            DPGroupName                       = $txtDPGroup.Text
            LimitingCollectionName            = $txtLimitingCollection.Text
            ApplicationFolder                 = $txtAppFolder.Text
            CollectionFolder                  = $txtCollectionFolder.Text
            MaxRuntimeMins                    = [int]$numMaxRuntime.Value
            CollectionCreationTimeoutMinutes  = [int]$numCollectionTimeout.Value
        }

        # Add optional collection names
        if (-not [string]::IsNullOrWhiteSpace($txtInstallCollection.Text)) {
            $params.InstallCollectionName = $txtInstallCollection.Text
        }

        if (-not [string]::IsNullOrWhiteSpace($txtUninstallCollection.Text)) {
            $params.UninstallCollectionName = $txtUninstallCollection.Text
        }

        # Add logging if enabled
        if ($chkEnableLogging.Checked -and -not [string]::IsNullOrWhiteSpace($txtLogPath.Text)) {
            $params.LogFilePath = $txtLogPath.Text
            Write-LogOutput -Message "File logging enabled: $($txtLogPath.Text)" -LogBox $rtbLog
        }

        # Add switches
        if ($chkForce.Checked) {
            $params.Force = $true
            Write-LogOutput -Message "Force mode enabled" -LogBox $rtbLog
        }

        if ($chkNoRollback.Checked) {
            $params.NoRollback = $true
            Write-LogOutput -Message "Rollback disabled" -LogBox $rtbLog
        }

        if ($WhatIfMode) {
            $params.WhatIf = $true
        }

        $params.Confirm = $false

        Write-LogOutput -Message "Invoking deployment script..." -LogBox $rtbLog
        Write-LogOutput -Message "" -LogBox $rtbLog

        # Execute script and capture output
        $job = Start-Job -ScriptBlock {
            param($ScriptPath, $Params)
            & $ScriptPath @Params 2>&1
        } -ArgumentList $scriptPath, $params

        # Monitor job output
        while ($job.State -eq 'Running') {
            $output = Receive-Job -Job $job
            if ($output) {
                foreach ($line in $output) {
                    Write-LogOutput -Message $line -LogBox $rtbLog
                }
            }
            Start-Sleep -Milliseconds 500
        }

        # Get final output
        $finalOutput = Receive-Job -Job $job
        if ($finalOutput) {
            foreach ($line in $finalOutput) {
                Write-LogOutput -Message $line -LogBox $rtbLog
            }
        }

        Remove-Job -Job $job -Force

        Write-LogOutput -Message "" -LogBox $rtbLog
        Write-LogOutput -Message "========================================" -LogBox $rtbLog

        if ($job.State -eq 'Completed') {
            Write-LogOutput -Message "EXECUTION COMPLETED" -LogBox $rtbLog

            [System.Windows.Forms.MessageBox]::Show(
                "Deployment script execution completed.`r`n`r`nCheck the Execution Log tab for details.",
                "Success",
                'OK',
                'Information'
            )
        }
        else {
            Write-LogOutput -Message "EXECUTION FAILED OR WAS INTERRUPTED" -LogBox $rtbLog

            [System.Windows.Forms.MessageBox]::Show(
                "Deployment script execution encountered an error.`r`n`r`nCheck the Execution Log tab for details.",
                "Error",
                'OK',
                'Error'
            )
        }

        Write-LogOutput -Message "========================================" -LogBox $rtbLog
    }
    catch {
        Write-LogOutput -Message "ERROR: $_" -LogBox $rtbLog
        Write-LogOutput -Message $_.ScriptStackTrace -LogBox $rtbLog

        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred:`r`n`r`n$_",
            "Error",
            'OK',
            'Error'
        )
    }
    finally {
        # Re-enable buttons
        $btnWhatIf.Enabled = $true
        $btnDeploy.Enabled = $true
    }
}

$btnWhatIf.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will run the deployment script in WhatIf mode.`r`n`r`nNo changes will be made to SCCM.`r`n`r`nContinue?",
        "Confirm WhatIf",
        'YesNo',
        'Question'
    )

    if ($result -eq 'Yes') {
        Invoke-Deployment -WhatIfMode $true
    }
})

$btnDeploy.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "This will deploy the application to SCCM.`r`n`r`nApplication: $($txtAppName.Text)`r`nSite: $($txtSiteCode.Text)`r`n`r`nAre you sure you want to continue?",
        "Confirm Deployment",
        'YesNo',
        'Warning'
    )

    if ($result -eq 'Yes') {
        Invoke-Deployment -WhatIfMode $false
    }
})

#endregion

# Show form
[void]$form.ShowDialog()
