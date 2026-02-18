<#
.SYNOPSIS
    Consolidated Web-based GUI for SCCM Application Deployment

.DESCRIPTION
    Launches a web server providing an HTML interface for deploying SCCM applications.
    All deployment logic is embedded — no external script dependency required.
    Accessible from network on port 80.

.NOTES
    Author: Consolidated from Deploy-SCCMApplication-Improved.ps1 + Web GUI
    Version: 2.0
    Requires: PowerShell 5.1+, ConfigurationManager module, Modern web browser
#>

[CmdletBinding()]
param()

$Port = 80
$ErrorActionPreference = 'Stop'

# Hardcoded SCCM settings
$script:SiteCode = 'CM0'
$script:SiteServer = 'WAZEU2PRDDE051.corp.internal.citizensbank.com'

# Global variables for state management
$script:LogMessages = @()
$script:IsDeploying = $false
$script:CurrentRunspace = $null
$script:CurrentRunspaceHandle = $null   # The underlying Runspace object (for STA/cleanup)
$script:CurrentAsyncResult = $null
$script:OutputCollection = $null

#region Deployment Logic (runs inside a runspace)

$script:DeploymentScriptBlock = {
    param([hashtable]$Config)

    # Extract parameters from config hashtable
    $AppName                          = $Config.AppName
    $Description                      = if ($Config.Description) { $Config.Description } else { "" }
    $SiteCode                         = $Config.SiteCode
    $SiteServerFqdn                   = $Config.SiteServerFqdn
    $ContentLocation                  = $Config.ContentLocation
    $InstallCommand                   = $Config.InstallCommand
    $UninstallCommand                 = if ($Config.UninstallCommand) { $Config.UninstallCommand } else { "" }
    $DeploymentTypeName               = $Config.DeploymentTypeName
    $DPGroupName                      = $Config.DPGroupName
    $LimitingCollectionName           = $Config.LimitingCollectionName
    $InstallCollectionName            = $Config.InstallCollectionName
    $UninstallCollectionName          = $Config.UninstallCollectionName
    $ApplicationFolder                = if ($Config.ApplicationFolder) { $Config.ApplicationFolder } else { "" }
    $CollectionFolder                 = if ($Config.CollectionFolder) { $Config.CollectionFolder } else { "" }
    $MaxRuntimeMins                   = if ($Config.MaxRuntimeMins) { $Config.MaxRuntimeMins } else { 60 }
    $CollectionCreationTimeoutMinutes = if ($Config.CollectionCreationTimeoutMinutes) { $Config.CollectionCreationTimeoutMinutes } else { 5 }
    $LogFilePath                      = $Config.LogFilePath
    $Force                            = [bool]$Config.Force
    $NoRollback                       = [bool]$Config.NoRollback
    $VerboseLogging                   = [bool]$Config.VerboseLogging
    $WhatIf                           = [bool]$Config.WhatIf

    $ErrorActionPreference = 'Stop'

    # Auto-generate names based on AppName if not provided
    if ([string]::IsNullOrWhiteSpace($DeploymentTypeName)) {
        $DeploymentTypeName = "${AppName}_Install"
    }
    if ([string]::IsNullOrWhiteSpace($InstallCollectionName)) {
        $InstallCollectionName = $AppName
    }
    if ([string]::IsNullOrWhiteSpace($UninstallCollectionName)) {
        $UninstallCollectionName = "${AppName}_Uninstall"
    }

    # Track created objects for rollback
    $createdObjects = @{
        Application = $null
        Collections = @()
        Deployments = @()
    }

    #--- Logging ---
    function Write-Log {
        param(
            [string]$Message = "",
            [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step')]
            [string]$Level = 'Info'
        )

        if ([string]::IsNullOrWhiteSpace($Message)) {
            Write-Output ""
            return
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        switch ($Level) {
            'Step'    { Write-Output "[$timestamp] [STEP] $Message" }
            'Success' { Write-Output "[$timestamp] [ OK ] $Message" }
            'Warning' { Write-Output "[$timestamp] [WARN] $Message" }
            'Error'   { Write-Output "[$timestamp] [FAIL] $Message" }
            default   { Write-Output "[$timestamp] [INFO] $Message" }
        }

        # File output if specified
        if ($LogFilePath) {
            try {
                "[$timestamp] [$Level] $Message" | Out-File -FilePath $LogFilePath -Append -ErrorAction SilentlyContinue
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
                    if ($line) { Write-Log -Message "  [VERBOSE] $line" -Level 'Info' }
                }
            } else {
                $null = & $Script
            }
            Write-Log -Message "$Name completed." -Level 'Success'
        }
        catch {
            Write-Log -Message "$Name failed." -Level 'Error'
            Write-Log -Message "Error: $_" -Level 'Error'
            if ($_.Exception.InnerException) {
                Write-Log -Message "InnerException: $($_.Exception.InnerException)" -Level 'Error'
            }
            if (-not $ContinueOnError) { throw }
        }
    }

    #--- Rollback ---
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

    #--- Main Deployment Execution ---
    try {
        $originalLocation = Get-Location

        Write-Log "========================================" -Level 'Info'
        Write-Log "SCCM Application Deployment Script" -Level 'Info'
        Write-Log "Application: $AppName" -Level 'Info'
        Write-Log "Site: $SiteCode ($SiteServerFqdn)" -Level 'Info'
        Write-Log "========================================" -Level 'Info'

        if ($WhatIf) {
            Write-Log "Running in WhatIf mode - no changes will be made" -Level 'Warning'
        }

        # Parameter summary
        if ($VerboseLogging -or $WhatIf) {
            Write-Log ""
            Write-Log "=== PARAMETER VALUES ===" -Level 'Info'
            Write-Log "AppName: $AppName" -Level 'Info'
            Write-Log "Description: $Description" -Level 'Info'
            Write-Log "SiteCode: $SiteCode" -Level 'Info'
            Write-Log "SiteServerFqdn: $SiteServerFqdn" -Level 'Info'
            Write-Log "ContentLocation: $ContentLocation" -Level 'Info'
            Write-Log "InstallCommand: $InstallCommand" -Level 'Info'
            Write-Log "UninstallCommand: $UninstallCommand" -Level 'Info'
            Write-Log "DeploymentTypeName: $DeploymentTypeName" -Level 'Info'
            Write-Log "DPGroupName: $DPGroupName" -Level 'Info'
            Write-Log "LimitingCollectionName: $LimitingCollectionName" -Level 'Info'
            Write-Log "InstallCollectionName: $InstallCollectionName" -Level 'Info'
            Write-Log "UninstallCollectionName: $UninstallCollectionName" -Level 'Info'
            Write-Log "ApplicationFolder: $ApplicationFolder" -Level 'Info'
            Write-Log "CollectionFolder: $CollectionFolder" -Level 'Info'
            Write-Log "MaxRuntimeMins: $MaxRuntimeMins" -Level 'Info'
            Write-Log "LogFilePath: $LogFilePath" -Level 'Info'
            Write-Log "Force: $Force" -Level 'Info'
            Write-Log "NoRollback: $NoRollback" -Level 'Info'
            Write-Log "WhatIf: $WhatIf" -Level 'Info'
            Write-Log "VerboseLogging: $VerboseLogging" -Level 'Info'
            Write-Log "=======================" -Level 'Info'
            Write-Log ""
        }

        #--- Pre-flight Validation ---
        Invoke-Step -Name "Pre-flight validation" -Script {
            Write-Log "Current User: $env:USERNAME" -Level 'Info'
            Write-Log "Current Computer: $env:COMPUTERNAME" -Level 'Info'

            # Check SMS_ADMIN_UI_PATH
            if (-not $env:SMS_ADMIN_UI_PATH) {
                throw "SMS_ADMIN_UI_PATH environment variable not found. Ensure ConfigMgr console is installed."
            }
            Write-Log "SMS_ADMIN_UI_PATH: $env:SMS_ADMIN_UI_PATH" -Level 'Info'

            # Check module path
            $modulePath = $env:SMS_ADMIN_UI_PATH.Substring(0, $env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1'
            if (-not (Test-Path $modulePath)) {
                throw "ConfigurationManager module not found at: $modulePath"
            }
            Write-Log "ConfigMgr module found" -Level 'Info'

            # Check content location
            Write-Log "Checking content location: $ContentLocation" -Level 'Info'
            if (-not (Test-Path $ContentLocation -PathType Container)) {
                throw "Content location not accessible: $ContentLocation"
            }
            Write-Log "Content location accessible" -Level 'Info'

            # Check install file (skip if command contains DOS variables like %ProgramFiles%)
            if ($InstallCommand -match '%.*%') {
                Write-Log "Install command contains environment variable(s) - skipping file validation" -Level 'Info'
            } else {
                $installFile = Join-Path $ContentLocation $InstallCommand
                if (-not (Test-Path $installFile)) {
                    throw "Installation command file not found: $installFile"
                }
                Write-Log "Install file found" -Level 'Info'
            }

            # Check uninstall file (optional)
            if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
                if ($UninstallCommand -match '%.*%') {
                    Write-Log "Uninstall command contains environment variable(s) - skipping file validation" -Level 'Info'
                } else {
                    $uninstallFile = Join-Path $ContentLocation $UninstallCommand
                    if (-not (Test-Path $uninstallFile)) {
                        Write-Log "Uninstall command file not found: $uninstallFile (continuing)" -Level 'Warning'
                    }
                }
            }
        }

        #--- Import SCCM Module & Connect ---
        Invoke-Step -Name "Import ConfigurationManager module & connect to site" -Script {
            Import-Module ($env:SMS_ADMIN_UI_PATH.Substring(0, $env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
            Set-Location "${SiteCode}:\" -ErrorAction Stop
        }

        #--- Deployment Steps ---
        try {
            # Remove existing application if present
            Invoke-Step -Name "Check and remove existing application '$AppName'" -Script {
                $existingDeployments = Get-CMApplicationDeployment -Name $AppName -ErrorAction SilentlyContinue
                if ($existingDeployments) {
                    Write-Log "Found $($existingDeployments.Count) existing deployment(s)" -Level 'Info'
                    if (-not $WhatIf) {
                        foreach ($deployment in $existingDeployments) {
                            Remove-CMApplicationDeployment -InputObject $deployment -Force -ErrorAction Stop
                            Write-Log "Removed deployment to: $($deployment.CollectionName)" -Level 'Success'
                        }
                    } else {
                        Write-Log "[WHATIF] Would remove $($existingDeployments.Count) existing deployment(s)" -Level 'Info'
                    }
                }

                $existing = Get-CMApplication -Name $AppName -Fast -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-Log "Found existing application '$AppName'" -Level 'Info'
                    if (-not $WhatIf) {
                        Remove-CMApplication -Name $AppName -Force -ErrorAction Stop
                        Write-Log "Removed existing application" -Level 'Success'
                    } else {
                        Write-Log "[WHATIF] Would remove existing application '$AppName'" -Level 'Info'
                    }
                }
            }

            # Create application
            Invoke-Step -Name "Create application '$AppName'" -Script {
                if (-not $WhatIf) {
                    New-CMApplication -Name $AppName -Description $Description -ErrorAction Stop | Out-Null
                    $createdObjects.Application = $AppName
                } else {
                    Write-Log "[WHATIF] Would create application '$AppName'" -Level 'Info'
                }
            }

            # Build detection clauses
            Write-Log "Building detection rules" -Level 'Step'

            $clause1 = New-CMDetectionClauseRegistryKeyValue `
                -Hive LocalMachine `
                -KeyName "Software\Microsoft\Office\ClickToRun\Configuration" `
                -ValueName "VersionToReport" `
                -PropertyType Version `
                -ExpressionOperator GreaterEquals `
                -ExpectedValue "16.0.11929.20562" `
                -Is64Bit $true

            $clause2 = New-CMDetectionClauseRegistryKeyValue `
                -Hive LocalMachine `
                -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ProPlus2024Volume - en-us" `
                -ValueName "DisplayName" `
                -PropertyType String `
                -ExpressionOperator IsEquals `
                -ExpectedValue "Microsoft Office LTSC Professional Plus 2024 - en-us" `
                -Is64Bit $true

            Write-Log "Detection clauses created successfully" -Level 'Success'

            # Add deployment type with detection
            Invoke-Step -Name "Add Script/EXE deployment type" -Script {
                if (-not $WhatIf) {
                    $dtParams = @{
                        ApplicationName           = $AppName
                        DeploymentTypeName        = $DeploymentTypeName
                        ContentLocation           = $ContentLocation
                        InstallCommand            = $InstallCommand
                        UninstallCommand          = $UninstallCommand
                        InstallationBehaviorType  = 'InstallForSystem'
                        LogonRequirementType      = 'WhetherOrNotUserLoggedOn'
                        UserInteractionMode       = 'Hidden'
                        MaximumRuntimeMins        = $MaxRuntimeMins
                        RebootBehavior            = 'BasedOnExitCode'
                        SlowNetworkDeploymentMode = 'Download'
                    }

                    Add-CMScriptDeploymentType @dtParams `
                        -ContentFallback `
                        -EnableBranchCache `
                        -AddDetectionClause $clause1, $clause2 `
                        -ErrorAction Stop | Out-Null

                    Write-Log "Deployment type created with 2 detection rules (AND logic)" -Level 'Success'
                } else {
                    Write-Log "[WHATIF] Would add deployment type '$DeploymentTypeName' with detection rules" -Level 'Info'
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
                    Write-Log "[WHATIF] Would set OS requirement to Windows 11 x64/ARM64" -Level 'Info'
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
                    Write-Log "[WHATIF] Would distribute content to '$DPGroupName'" -Level 'Info'
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

                        Write-Log "Collection created, waiting for provider replication..." -Level 'Info'
                        $timeout = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
                        $retryCount = 0
                        do {
                            Start-Sleep -Seconds 3
                            $retryCount++
                            $existing = Get-CMDeviceCollection -Name $InstallCollectionName -ErrorAction SilentlyContinue
                            if ($existing) {
                                Write-Log "Collection verified after $retryCount attempts" -Level 'Success'
                                break
                            }
                            if ([datetime]::UtcNow -gt $timeout) {
                                throw "Collection creation timed out after $CollectionCreationTimeoutMinutes minutes."
                            }
                        } while (-not $existing)

                        $createdObjects.Collections += $InstallCollectionName
                    } else {
                        Write-Log "[WHATIF] Would create device collection '$InstallCollectionName'" -Level 'Info'
                    }
                } else {
                    Write-Log "Collection '$InstallCollectionName' already exists" -Level 'Info'
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

                        Write-Log "Collection created, waiting for provider replication..." -Level 'Info'
                        $timeout = [datetime]::UtcNow.AddMinutes($CollectionCreationTimeoutMinutes)
                        $retryCount = 0
                        do {
                            Start-Sleep -Seconds 3
                            $retryCount++
                            $existing = Get-CMDeviceCollection -Name $UninstallCollectionName -ErrorAction SilentlyContinue
                            if ($existing) {
                                Write-Log "Collection verified after $retryCount attempts" -Level 'Success'
                                break
                            }
                            if ([datetime]::UtcNow -gt $timeout) {
                                throw "Collection creation timed out after $CollectionCreationTimeoutMinutes minutes."
                            }
                        } while (-not $existing)

                        $createdObjects.Collections += $UninstallCollectionName
                    } else {
                        Write-Log "[WHATIF] Would create device collection '$UninstallCollectionName'" -Level 'Info'
                    }
                } else {
                    Write-Log "Collection '$UninstallCollectionName' already exists" -Level 'Info'
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
                        Write-Log "Waiting for collection replication... (attempt $retries/$maxRetries)" -Level 'Info'
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
                    Write-Log "[WHATIF] Would create Install/Required deployment to '$InstallCollectionName'" -Level 'Info'
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
                        Write-Log "[WHATIF] Would move application to '$fullPath'" -Level 'Info'
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
                            Write-Log "Moved collection: $collName" -Level 'Info'
                        } else {
                            Write-Log "[WHATIF] Would move collection '$collName' to '$fullPath'" -Level 'Info'
                        }
                    }
                }
            }

            Write-Log "" -Level 'Info'
            Write-Log "========================================" -Level 'Success'
            Write-Log "ALL STEPS COMPLETED SUCCESSFULLY" -Level 'Success'
            Write-Log "Application: $AppName" -Level 'Success'
            Write-Log "========================================" -Level 'Success'
        }
        catch {
            Write-Log "Deployment failed: $_" -Level 'Error'

            if (-not $NoRollback -and $createdObjects.Application) {
                Invoke-Rollback
            }

            throw
        }
    }
    catch {
        Write-Log "Script execution failed: $_" -Level 'Error'
    }
    finally {
        # Return to original location
        try {
            if ((Get-Location).Provider.Name -eq 'CMSite' -and $originalLocation) {
                Set-Location $originalLocation.Path -ErrorAction SilentlyContinue
            }
        } catch {}

        if ($LogFilePath) {
            Write-Log "Log file saved to: $LogFilePath" -Level 'Info'
        }
    }
}

#endregion

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
    if ($type) { return $type }
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

        .input-error {
            border-color: #e74c3c !important;
            background-color: #fef5f5 !important;
        }

        .error-message {
            color: #e74c3c;
            font-size: 12px;
            margin-top: 5px;
            display: none;
        }

        .error-message.visible {
            display: block;
        }

        .validation-summary {
            background-color: #fef5f5;
            border: 2px solid #e74c3c;
            border-radius: 6px;
            padding: 15px;
            margin-bottom: 20px;
            display: none;
        }

        .validation-summary.visible {
            display: block;
        }

        .validation-summary h3 {
            color: #e74c3c;
            margin-bottom: 10px;
            font-size: 16px;
        }

        .validation-summary ul {
            margin: 0;
            padding-left: 20px;
        }

        .validation-summary li {
            color: #721c24;
            margin-bottom: 5px;
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
            <button class="tab active" onclick="switchTab('config')">Configuration</button>
            <button class="tab" onclick="switchTab('options')">Options</button>
            <button class="tab" onclick="switchTab('log')">Execution Log</button>
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
                    <input type="text" id="appName" value="" placeholder="e.g., MyApp_v1.0">
                    <div class="error-message" id="appName-error">Application Name is required</div>
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

            <fieldset class="fieldset">
                <legend>Content Settings</legend>

                <div class="form-group">
                    <label class="required">Content Location (UNC Path)</label>
                    <input type="text" id="contentLocation" value="" placeholder="\\server\share\folder">
                    <div class="error-message" id="contentLocation-error">Content Location is required and must be a UNC path (\\server\share\folder)</div>
                    <div class="help-text">Network path to application source files (type the full UNC path manually)</div>
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label class="required">Install Command</label>
                        <input type="text" id="installCmd" value="" placeholder="setup.exe /silent">
                        <div class="error-message" id="installCmd-error">Install Command is required</div>
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
                <legend>Collections & Distribution</legend>

                <div class="form-group">
                    <label class="required">Limiting Collection</label>
                    <input type="text" id="limitingCollection" value="" placeholder="All Desktop and Server Clients">
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
                    <label class="required">Distribution Point Group</label>
                    <input type="text" id="dpGroup" value="" placeholder="All Distribution Points">
                    <div class="error-message" id="dpGroup-error">Distribution Point Group is required</div>
                </div>
            </fieldset>

            <fieldset class="fieldset">
                <legend>Console Organization</legend>

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

            <div class="form-group checkbox-group">
                <input type="checkbox" id="verboseLogging" checked>
                <label for="verboseLogging">Enable verbose logging (recommended during testing)</label>
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
                WhatIf (Test Run)
            </button>
            <button class="btn btn-deploy" id="btnDeploy" onclick="startDeployment(false)">
                Deploy
            </button>
        </div>
    </div>

    <script>
        let logRefreshInterval = null;
        let validationErrors = {};

        // Required fields configuration
        const requiredFields = {
            'appName': 'Application Name',
            'contentLocation': 'Content Location',
            'installCmd': 'Install Command',
            'limitingCollection': 'Limiting Collection',
            'dpGroup': 'Distribution Point Group'
        };

        function validateField(fieldId) {
            const field = document.getElementById(fieldId);
            const errorDiv = document.getElementById(fieldId + '-error');
            const value = field.value.trim();
            let isValid = true;
            let errorMessage = '';

            // Check if required field is empty
            if (requiredFields[fieldId] && !value) {
                isValid = false;
                errorMessage = requiredFields[fieldId] + ' is required';
            }

            // Special validation for Content Location (must be UNC path)
            if (fieldId === 'contentLocation' && value && !value.startsWith('\\\\')) {
                isValid = false;
                errorMessage = 'Content Location must be a UNC path (e.g., \\\\server\\share\\folder)';
            }

            // Update UI
            if (isValid) {
                field.classList.remove('input-error');
                if (errorDiv) {
                    errorDiv.classList.remove('visible');
                }
                delete validationErrors[fieldId];
            } else {
                field.classList.add('input-error');
                if (errorDiv) {
                    errorDiv.textContent = errorMessage;
                    errorDiv.classList.add('visible');
                }
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
                if (!validateField(fieldId)) {
                    allValid = false;
                }
            }

            return allValid;
        }

        function updateValidationSummary() {
            const summary = document.getElementById('validationSummary');
            const errorList = document.getElementById('validationErrors');
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
            const hasErrors = Object.keys(validationErrors).length > 0;
            const isDeploying = document.getElementById('statusBadge').classList.contains('status-deploying');

            document.getElementById('btnWhatIf').disabled = hasErrors || isDeploying;
            document.getElementById('btnDeploy').disabled = hasErrors || isDeploying;
        }

        function switchTab(tabName) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));

            // Find and activate the clicked tab
            const tabs = document.querySelectorAll('.tab');
            tabs.forEach(tab => {
                if (tab.textContent.includes(tabName === 'config' ? 'Configuration' : tabName === 'options' ? 'Options' : 'Log')) {
                    tab.classList.add('active');
                }
            });

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

            if (isDeploying) {
                badge.className = 'status-badge status-deploying';
                badge.innerHTML = '<span class="spinner"></span> Deploying...';
            } else {
                badge.className = 'status-badge status-ready';
                badge.textContent = 'Ready';
            }

            updateButtonStates();
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
            const allValid = validateAllFields();

            const appFolder = document.getElementById('appFolder').value.trim();
            const collFolder = document.getElementById('collectionFolder').value.trim();

            if (appFolder && /[<>:"|?*]/.test(appFolder)) {
                alert('Application Folder Path contains illegal characters (<>:"|?*)');
                return false;
            }

            if (collFolder && /[<>:"|?*]/.test(collFolder)) {
                alert('Collection Folder Path contains illegal characters (<>:"|?*)');
                return false;
            }

            if (!allValid) {
                switchTab('config');
                return false;
            }

            return true;
        }

        function getConfig() {
            return {
                AppName: document.getElementById('appName').value,
                Description: document.getElementById('description').value,
                SiteCode: 'CM0',
                SiteServerFqdn: 'WAZEU2PRDDE051.corp.internal.citizensbank.com',
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
                NoRollback: document.getElementById('noRollback').checked,
                VerboseLogging: document.getElementById('verboseLogging').checked
            };
        }

        function startDeployment(whatIf) {
            if (!validateInputs()) {
                return;
            }

            const mode = whatIf ? 'WhatIf' : 'Deploy';
            const confirmed = confirm(`Start deployment in ${mode} mode?\n\nApplication: ${document.getElementById('appName').value}\nSite: CM0 @ WAZEU2PRDDE051.corp.internal.citizensbank.com`);

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

        // Initialize real-time validation and auto-refresh
        document.addEventListener('DOMContentLoaded', () => {
            for (const fieldId in requiredFields) {
                const field = document.getElementById(fieldId);
                if (field) {
                    field.addEventListener('blur', () => validateField(fieldId));
                    field.addEventListener('input', () => {
                        if (field.value.trim()) {
                            validateField(fieldId);
                        }
                    });
                }
            }

            validateAllFields();

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

    # Collect output from runspace if deployment is running
    if ($script:CurrentRunspace -and $script:CurrentAsyncResult) {
        try {
            # Read any available output from the PSDataCollection (real-time)
            if ($script:OutputCollection) {
                $newMessages = @()
                $count = $script:OutputCollection.Count
                for ($i = 0; $i -lt $count; $i++) {
                    $line = "$($script:OutputCollection[$i])"
                    if ($line) { $newMessages += $line }
                }
                if ($newMessages.Count -gt 0) {
                    # Keep the initial header messages and append live output
                    $headerCount = 0
                    foreach ($msg in $script:LogMessages) {
                        if ($msg -match '^===|^Timestamp:|^Mode:|^Application:|^Site:|^Content:|^Install Cmd:|^Uninstall Cmd:|^={3,}$|^$|^Starting deployment') {
                            $headerCount++
                        } else {
                            break
                        }
                    }
                    $header = @()
                    if ($headerCount -gt 0 -and $headerCount -le $script:LogMessages.Count) {
                        $header = $script:LogMessages[0..($headerCount - 1)]
                    }
                    $script:LogMessages = $header + $newMessages
                }
            }

            if ($script:CurrentAsyncResult.IsCompleted) {
                # Get any final output
                try {
                    $finalOutput = $script:CurrentRunspace.EndInvoke($script:CurrentAsyncResult)
                } catch {}

                # Check for errors in streams
                if ($script:CurrentRunspace.Streams.Error.Count -gt 0) {
                    foreach ($err in $script:CurrentRunspace.Streams.Error) {
                        $script:LogMessages += "[ERROR] $err"
                    }
                }

                $script:LogMessages += ""
                $script:LogMessages += "========================================="
                $script:LogMessages += "DEPLOYMENT PROCESS FINISHED"
                $script:LogMessages += "========================================="

                $script:CurrentRunspace.Dispose()
                $script:CurrentRunspace = $null
                if ($script:CurrentRunspaceHandle) {
                    $script:CurrentRunspaceHandle.Close()
                    $script:CurrentRunspaceHandle.Dispose()
                    $script:CurrentRunspaceHandle = $null
                }
                $script:CurrentAsyncResult = $null
                $script:OutputCollection = $null
                $script:IsDeploying = $false
            }
        }
        catch {
            $script:LogMessages += "Error reading deployment output: $_"
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

    # Build config hashtable for the deployment scriptblock
    $params = @{
        AppName                          = $config.AppName
        Description                      = $config.Description
        SiteCode                         = $config.SiteCode
        SiteServerFqdn                   = $config.SiteServerFqdn
        ContentLocation                  = $config.ContentLocation
        InstallCommand                   = $config.InstallCommand
        UninstallCommand                 = $config.UninstallCommand
        DeploymentTypeName               = $config.DeploymentTypeName
        DPGroupName                      = $config.DPGroupName
        LimitingCollectionName           = $config.LimitingCollectionName
        InstallCollectionName            = $config.InstallCollectionName
        UninstallCollectionName          = $config.UninstallCollectionName
        ApplicationFolder                = $config.ApplicationFolder
        CollectionFolder                 = $config.CollectionFolder
        MaxRuntimeMins                   = $config.MaxRuntimeMins
        CollectionCreationTimeoutMinutes = $config.CollectionCreationTimeoutMinutes
        LogFilePath                      = $config.LogFilePath
        Force                            = [bool]$config.Force
        NoRollback                       = [bool]$config.NoRollback
        VerboseLogging                   = [bool]$config.VerboseLogging
        WhatIf                           = [bool]$config.WhatIf
    }

    # Run deployment in a PowerShell runspace with STA threading.
    # SCCM's ConfigurationManager module uses COM/DCOM components that require
    # Single-Threaded Apartment (STA) model — the same model used by interactive
    # PowerShell sessions. Default runspaces use MTA which breaks WMI calls.
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
    $runspace.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript($script:DeploymentScriptBlock).AddArgument($params) | Out-Null

    # Use PSDataCollection for real-time output streaming
    $script:OutputCollection = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'
    $inputCollection = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'
    $inputCollection.Complete()

    $script:CurrentRunspaceHandle = $runspace
    $script:CurrentRunspace = $ps
    $script:CurrentAsyncResult = $ps.BeginInvoke($inputCollection, $script:OutputCollection)

    $script:LogMessages += "Starting deployment (STA runspace, same process context)..."
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
    Write-Host ""
    Write-Host "NOTE: This is a consolidated script - no external dependency required." -ForegroundColor Green
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

    # Clean up any running runspaces
    if ($script:CurrentRunspace) {
        try {
            $script:CurrentRunspace.Stop()
            $script:CurrentRunspace.Dispose()
        }
        catch {}
    }
    if ($script:CurrentRunspaceHandle) {
        try {
            $script:CurrentRunspaceHandle.Close()
            $script:CurrentRunspaceHandle.Dispose()
        }
        catch {}
    }

    Write-Host "`nServer stopped." -ForegroundColor Yellow
}
