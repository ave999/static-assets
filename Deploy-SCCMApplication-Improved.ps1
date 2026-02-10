<#
.SYNOPSIS
    Automated SCCM application deployment script with robust error handling and validation.

.DESCRIPTION
    Creates an SCCM application with deployment type, detection rules, content distribution,
    device collections, and deployments. Includes pre-flight validation, rollback capabilities,
    and comprehensive logging.

.PARAMETER AppName
    Name of the application to create in SCCM.

.PARAMETER SiteCode
    SCCM site code (e.g., '365').

.PARAMETER SiteServerFqdn
    Fully qualified domain name of the SCCM site server.

.PARAMETER ContentLocation
    UNC path to the application source files.

.PARAMETER InstallCommand
    Command line for installation.

.PARAMETER UninstallCommand
    Command line for uninstallation.

.PARAMETER DPGroupName
    Distribution Point group name for content distribution.

.PARAMETER LimitingCollectionName
    Name of the limiting collection for device collections.

.PARAMETER LogFilePath
    Optional path for log file. If not specified, logs to console only.

.PARAMETER WhatIf
    Shows what would happen if the script runs without making changes.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Deploy-SCCMApplication-Improved.ps1 -AppName "MSCPPROJECTSTD_2024_00S00_P" -WhatIf

.EXAMPLE
    .\Deploy-SCCMApplication-Improved.ps1 -AppName "MyApp" -LogFilePath "C:\Logs\deployment.log" -Force

.NOTES
    Author: Improved version based on audit recommendations
    Version: 2.0
    Requires: ConfigurationManager PowerShell module, appropriate SCCM permissions
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AppName = 'MSCPPROJECTSTD_2024_00S00_P',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteCode = '365',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServerFqdn = 'eusdevptp3.namdev.nsrootdev.net',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Description = "Custom application - scripted install",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ContentLocation = '\\eusdevptp3\SCCMSource\Applications\Defender',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallCommand = 'InstallProjectSTD2024.cmd',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$UninstallCommand = 'RemoveProjectSTD2024.cmd',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DPGroupName = 'All Distribution Points',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LimitingCollectionName = 'All Desktop and Server Clients',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$DeploymentTypeName = 'MSCPPROJECTSTD_2024_00S00_DEPLOY01',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallCollectionName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$UninstallCollectionName,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationFolder = 'Desktops\3. PROD',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CollectionFolder = 'Desktops\Applications\3. PROD',

    [Parameter(Mandatory = $false)]
    [int]$MaxRuntimeMins = 60,

    [Parameter(Mandatory = $false)]
    [int]$CollectionCreationTimeoutMinutes = 5,

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$NoRollback,

    [Parameter(Mandatory = $false)]
    [switch]$VerboseLogging
)

$ErrorActionPreference = 'Stop'
$script:CreatedObjects = @{
    Application = $null
    Collections = @()
    Deployments = @()
}

# Set default collection names based on AppName
if (-not $InstallCollectionName) {
    $InstallCollectionName = $AppName
}
if (-not $UninstallCollectionName) {
    $UninstallCollectionName = "${AppName}_Uninstall"
}

#region Logging Functions

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    # Console output with colors
    switch ($Level) {
        'Step'    { Write-Host "[STEP] $Message" -ForegroundColor Cyan }
        'Success' { Write-Host "[ OK ] $Message" -ForegroundColor Green }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Host "[FAIL] $Message" -ForegroundColor Red }
        default   { Write-Host "[INFO] $Message" }
    }

    # File output if specified
    if ($LogFilePath) {
        try {
            $logMessage | Out-File -FilePath $LogFilePath -Append -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $_"
        }
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Script,

        [switch]$ContinueOnError
    )

    Write-Log -Message $Name -Level 'Step'

    try {
        $result = & $Script
        Write-Log -Message "$Name completed." -Level 'Success'
        return $result
    }
    catch {
        Write-Log -Message "$Name failed." -Level 'Error'
        $_ | Format-List * -Force | Out-String | Write-Log -Level 'Error'

        if ($_.Exception.InnerException) {
            Write-Log -Message "InnerException: $($_.Exception.InnerException)" -Level 'Error'
        }

        if (-not $ContinueOnError) {
            throw
        }
    }
}

#endregion

#region Validation Functions

function Test-Prerequisites {
    param()

    Write-Log -Message "Running pre-flight validation..." -Level 'Step'

    # Check if SMS_ADMIN_UI_PATH exists
    Write-Log -Message "Checking SMS_ADMIN_UI_PATH environment variable..." -Level 'Info'
    if (-not $env:SMS_ADMIN_UI_PATH) {
        throw "SMS_ADMIN_UI_PATH environment variable not found. Ensure ConfigMgr console is installed."
    }
    Write-Log -Message "  Found: $env:SMS_ADMIN_UI_PATH" -Level 'Info'

    # Check if ConfigMgr module path exists
    $modulePath = Join-Path (Split-Path $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1'
    Write-Log -Message "Checking ConfigMgr module at: $modulePath" -Level 'Info'
    if (-not (Test-Path $modulePath)) {
        throw "ConfigurationManager module not found at: $modulePath"
    }
    Write-Log -Message "  Module found" -Level 'Info'

    # Check content location accessibility
    Write-Log -Message "Checking content location: $ContentLocation" -Level 'Info'
    if (-not (Test-Path $ContentLocation -PathType Container)) {
        throw "Content location not accessible: $ContentLocation. Verify path exists and you have permissions."
    }
    Write-Log -Message "  Content location accessible" -Level 'Info'

    # Check for required installation files
    $installFile = Join-Path $ContentLocation $InstallCommand
    Write-Log -Message "Checking install file: $installFile" -Level 'Info'
    if (-not (Test-Path $installFile)) {
        throw "Installation command file not found: $installFile"
    }
    Write-Log -Message "  Install file found" -Level 'Info'

    # Only check uninstall file if uninstall command was provided
    if (-not [string]::IsNullOrWhiteSpace($UninstallCommand)) {
        $uninstallFile = Join-Path $ContentLocation $UninstallCommand
        Write-Log -Message "Checking uninstall file: $uninstallFile" -Level 'Info'
        if (-not (Test-Path $uninstallFile)) {
            Write-Log -Message "  Uninstall command file not found: $uninstallFile (continuing)" -Level 'Warning'
        } else {
            Write-Log -Message "  Uninstall file found" -Level 'Info'
        }
    } else {
        Write-Log -Message "Uninstall command not provided - skipping file check" -Level 'Info'
    }

    Write-Log -Message "Pre-flight validation passed." -Level 'Success'
}

function Test-SCCMConnectivity {
    param(
        [Parameter(Mandatory)]
        [string]$SiteServer
    )

    try {
        $testConnection = Test-Connection -ComputerName $SiteServer -Count 1 -Quiet -ErrorAction Stop
        if (-not $testConnection) {
            throw "Cannot reach site server: $SiteServer"
        }
        return $true
    }
    catch {
        throw "Site server connectivity test failed: $_"
    }
}

#endregion

#region Rollback Functions

function Invoke-Rollback {
    param()

    if ($NoRollback) {
        Write-Log -Message "Rollback disabled by parameter. Manual cleanup required." -Level 'Warning'
        return
    }

    Write-Log -Message "Initiating rollback of created objects..." -Level 'Warning'

    # Remove deployments
    foreach ($deployment in $script:CreatedObjects.Deployments) {
        try {
            Write-Log -Message "Removing deployment: $deployment" -Level 'Info'
            Remove-CMApplicationDeployment -DeploymentId $deployment -Force -ErrorAction Stop
        }
        catch {
            Write-Log -Message "Failed to remove deployment $deployment`: $_" -Level 'Error'
        }
    }

    # Remove collections
    foreach ($collection in $script:CreatedObjects.Collections) {
        try {
            Write-Log -Message "Removing collection: $collection" -Level 'Info'
            Remove-CMDeviceCollection -Name $collection -Force -ErrorAction Stop
        }
        catch {
            Write-Log -Message "Failed to remove collection $collection`: $_" -Level 'Error'
        }
    }

    # Remove application
    if ($script:CreatedObjects.Application) {
        try {
            Write-Log -Message "Removing application: $($script:CreatedObjects.Application)" -Level 'Info'
            Remove-CMApplication -Name $script:CreatedObjects.Application -Force -ErrorAction Stop
        }
        catch {
            Write-Log -Message "Failed to remove application: $_" -Level 'Error'
        }
    }

    Write-Log -Message "Rollback completed. Verify SCCM console for any remaining objects." -Level 'Warning'
}

#endregion

#region SCCM Functions

function Initialize-SCCMEnvironment {
    param(
        [Parameter(Mandatory)]
        [string]$SiteCode,

        [Parameter(Mandatory)]
        [string]$SiteServer
    )

    Invoke-Step -Name "Import ConfigurationManager module & connect to site" -Script {
        # Import module
        $modulePath = Join-Path (Split-Path $env:SMS_ADMIN_UI_PATH) 'ConfigurationManager.psd1'
        Import-Module $modulePath -ErrorAction Stop

        # Test connectivity
        Test-SCCMConnectivity -SiteServer $SiteServer

        # Find or create site drive
        $cmDrive = Get-PSDrive -PSProvider CMSITE -ErrorAction SilentlyContinue |
                   Where-Object { $_.Root -eq $SiteServer } |
                   Select-Object -First 1

        if (-not $cmDrive) {
            Write-Log -Message "Creating new PSDrive for site $SiteCode" -Level 'Info'
            $cmDrive = New-PSDrive -Name $SiteCode -PSProvider 'AdminUI.PS.Provider\CMSite' -Root $SiteServer -ErrorAction Stop
        }

        if (-not $cmDrive) {
            throw "Failed to create or find SCCM site drive for $SiteServer"
        }

        # Change to site drive
        Push-Location "$($cmDrive.Name):"
        Write-Log -Message "Connected to SCCM site: $($cmDrive.Name)" -Level 'Info'
    }
}

function Remove-ExistingApplication {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    Invoke-Step -Name "Check and remove existing application '$Name'" -Script {
        # Remove deployments first
        $existingDeployments = Get-CMApplicationDeployment -Name $Name -ErrorAction SilentlyContinue

        if ($existingDeployments) {
            Write-Log -Message "Found $($existingDeployments.Count) existing deployment(s)" -Level 'Info'

            foreach ($deployment in $existingDeployments) {
                if ($PSCmdlet.ShouldProcess($deployment.CollectionName, "Remove deployment")) {
                    Remove-CMApplicationDeployment -InputObject $deployment -Force -ErrorAction Stop
                    Write-Log -Message "Removed deployment to: $($deployment.CollectionName)" -Level 'Success'
                }
            }
        }

        # Remove application
        $existing = Get-CMApplication -Name $Name -Fast -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Log -Message "Found existing application '$Name'" -Level 'Info'

            if ($PSCmdlet.ShouldProcess($Name, "Remove application")) {
                Remove-CMApplication -Name $Name -Force -ErrorAction Stop
                Write-Log -Message "Removed existing application" -Level 'Success'
            }
        }
    }
}

function New-ApplicationWithDetection {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [string]$ContentPath,

        [Parameter(Mandatory)]
        [string]$InstallCmd,

        [Parameter(Mandatory)]
        [string]$UninstallCmd,

        [Parameter(Mandatory)]
        [string]$DeployTypeName,

        [Parameter(Mandatory)]
        [int]$MaxRuntime
    )

    # Create application shell
    Invoke-Step -Name "Create application '$Name'" -Script {
        if ($PSCmdlet.ShouldProcess($Name, "Create application")) {
            New-CMApplication -Name $Name -Description $Description -ErrorAction Stop | Out-Null
            $script:CreatedObjects.Application = $Name
        }
    }

    # Build detection clauses - FIXED: Removed trailing -Value parameters
    Write-Log -Message "Building detection rules" -Level 'Step'

    # Detection clause 1: Office version check
    $clause1 = New-CMDetectionClauseRegistryKeyValue `
        -Hive LocalMachine `
        -KeyName "Software\Microsoft\Office\ClickToRun\Configuration" `
        -ValueName "VersionToReport" `
        -PropertyType Version `
        -ExpressionOperator GreaterEquals `
        -ExpectedValue "16.0.11929.20562" `
        -Is64Bit $true

    # Detection clause 2: Product name check
    $clause2 = New-CMDetectionClauseRegistryKeyValue `
        -Hive LocalMachine `
        -KeyName "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ProPlus2024Volume - en-us" `
        -ValueName "DisplayName" `
        -PropertyType String `
        -ExpressionOperator IsEquals `
        -ExpectedValue "Microsoft Office LTSC Professional Plus 2024 - en-us" `
        -Is64Bit $true

    Write-Log -Message "Detection clauses created successfully" -Level 'Success'

    # Add deployment type with detection
    Invoke-Step -Name "Add Script/EXE deployment type" -Script {
        if ($PSCmdlet.ShouldProcess($DeployTypeName, "Add deployment type")) {
            $dtParams = @{
                ApplicationName          = $Name
                DeploymentTypeName       = $DeployTypeName
                ContentLocation          = $ContentPath
                InstallCommand           = $InstallCmd
                UninstallCommand         = $UninstallCmd
                InstallationBehaviorType = 'InstallForSystem'
                LogonRequirementType     = 'WhetherOrNotUserLoggedOn'
                UserInteractionMode      = 'Hidden'
                MaximumRuntimeMins       = $MaxRuntime
                RebootBehavior           = 'BasedOnExitCode'
                SlowNetworkDeploymentMode = 'Download'
            }

            # FIXED: Simplified detection clause logic - using -AddDetectionClause with AND connector
            Add-CMScriptDeploymentType @dtParams `
                -ContentFallback `
                -EnableBranchCache `
                -AddDetectionClause $clause1, $clause2 `
                -ErrorAction Stop | Out-Null

            Write-Log -Message "Deployment type created with 2 detection rules (AND logic)" -Level 'Success'
        }
    }
}

function Set-DeploymentTypeRequirements {
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$DeployTypeName
    )

    Invoke-Step -Name "Add OS requirement (Windows 11 x64/ARM64)" -Script {
        if ($PSCmdlet.ShouldProcess($DeployTypeName, "Set OS requirements")) {
            # Get Operating System global condition
            $osGC = Get-CMGlobalCondition -Name "Operating System" |
                    Where-Object PlatformType -eq 1

            if (-not $osGC) {
                throw "Operating System global condition not found"
            }

            # Clear existing requirements
            Set-CMDeploymentType -ApplicationName $AppName `
                -DeploymentTypeName $DeployTypeName `
                -ClearRequirements -ErrorAction Stop | Out-Null

            # Create requirement rule for Windows 11 (both x64 and ARM64)
            $osRule = $osGC | New-CMRequirementRuleOperatingSystemValue `
                -PlatformString @(
                    'Windows/All_x64_Windows_11_and_higher_Clients',
                    'Windows/All_ARM64_Windows_11_and_higher_Clients'
                ) `
                -RuleOperator OneOf

            # Apply requirement
            Set-CMScriptDeploymentType -ApplicationName $AppName `
                -DeploymentTypeName $DeployTypeName `
                -AddRequirement $osRule -ErrorAction Stop | Out-Null

            Write-Log -Message "OS requirements configured: Windows 11 (x64 + ARM64)" -Level 'Success'
        }
    }
}

function Start-ContentDistributionToDP {
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$DPGroup
    )

    Invoke-Step -Name "Distribute content to DP group '$DPGroup'" -Script {
        # Verify DP group exists
        $dpGroup = Get-CMDistributionPointGroup -Name $DPGroup -ErrorAction SilentlyContinue

        if (-not $dpGroup) {
            throw "Distribution Point Group '$DPGroup' not found. Verify name and try again."
        }

        if ($PSCmdlet.ShouldProcess($DPGroup, "Distribute content")) {
            Start-CMContentDistribution -ApplicationName $AppName `
                -DistributionPointGroupName $DPGroup -ErrorAction Stop | Out-Null

            Write-Log -Message "Content distribution initiated to $($dpGroup.MemberCount) distribution point(s)" -Level 'Success'
        }
    }
}

function New-DeviceCollectionWithWait {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$LimiterName,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 5
    )

    Invoke-Step -Name "Create device collection '$Name'" -Script {
        # Verify limiting collection exists
        $limiter = Get-CMDeviceCollection -Name $LimiterName -ErrorAction SilentlyContinue

        if (-not $limiter) {
            throw "Limiting collection '$LimiterName' not found. Verify name and permissions."
        }

        # Check if collection already exists
        $existing = Get-CMDeviceCollection -Name $Name -ErrorAction SilentlyContinue

        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($Name, "Create collection")) {
                New-CMDeviceCollection -Name $Name `
                    -LimitingCollectionId $limiter.CollectionID `
                    -ErrorAction Stop | Out-Null

                Write-Log -Message "Collection created, waiting for provider replication..." -Level 'Info'

                # Wait for replication with timeout
                $timeout = [datetime]::UtcNow.AddMinutes($TimeoutMinutes)
                $retryCount = 0

                do {
                    Start-Sleep -Seconds 3
                    $retryCount++
                    $existing = Get-CMDeviceCollection -Name $Name -ErrorAction SilentlyContinue

                    if ($existing) {
                        Write-Log -Message "Collection verified after $retryCount attempts" -Level 'Success'
                        break
                    }

                    if ([datetime]::UtcNow -gt $timeout) {
                        throw "Collection creation timed out after $TimeoutMinutes minutes. Check SCCM provider status."
                    }
                } while (-not $existing)

                $script:CreatedObjects.Collections += $Name
            }
        }
        else {
            Write-Log -Message "Collection '$Name' already exists" -Level 'Info'
        }
    }
}

function New-ApplicationDeploymentWithWait {
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$CollectionName,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Uninstall')]
        [string]$DeployAction,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Available', 'Required')]
        [string]$DeployPurpose = 'Required'
    )

    $purposeText = if ($DeployPurpose -eq 'Required') { 'Required' } else { 'Available' }

    Invoke-Step -Name "Deploy '$AppName' to '$CollectionName' ($DeployAction / $purposeText)" -Script {
        # Verify collection exists with retries (handles replication lag)
        $retries = 0
        $maxRetries = 10
        $collection = $null

        do {
            $collection = Get-CMDeviceCollection -Name $CollectionName -ErrorAction SilentlyContinue

            if ($collection) { break }

            if ($retries -gt 0) {
                Write-Log -Message "Waiting for collection replication... (attempt $retries/$maxRetries)" -Level 'Info'
                Start-Sleep -Seconds 5
            }

            $retries++
        } while ($retries -le $maxRetries)

        if (-not $collection) {
            throw "Collection '$CollectionName' not found after $maxRetries retries. Check replication status."
        }

        if ($PSCmdlet.ShouldProcess($CollectionName, "Deploy application")) {
            $deployment = New-CMApplicationDeployment `
                -ApplicationName $AppName `
                -CollectionId $collection.CollectionID `
                -DeployAction $DeployAction `
                -DeployPurpose $DeployPurpose `
                -UserNotification DisplaySoftwareCenterOnly `
                -ErrorAction Stop

            $script:CreatedObjects.Deployments += $deployment.DeploymentID

            Write-Log -Message "Deployment created successfully (ID: $($deployment.DeploymentID))" -Level 'Success'
        }
    }
}

function Move-ApplicationToFolder {
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [string]$SiteCode
    )

    Invoke-Step -Name "Move application to folder '$FolderPath'" -Script {
        $fullPath = "${SiteCode}:\Application\${FolderPath}"

        if ($PSCmdlet.ShouldProcess($fullPath, "Move application")) {
            $app = Get-CMApplication -Name $AppName -ErrorAction Stop
            Move-CMObject -FolderPath $fullPath -InputObject $app -ErrorAction Stop

            Write-Log -Message "Application moved to folder" -Level 'Success'
        }
    }
}

function Move-CollectionsToFolder {
    param(
        [Parameter(Mandatory)]
        [string[]]$CollectionNames,

        [Parameter(Mandatory)]
        [string]$FolderPath,

        [Parameter(Mandatory)]
        [string]$SiteCode
    )

    Invoke-Step -Name "Move collections to folder '$FolderPath'" -Script {
        $fullPath = "${SiteCode}:\DeviceCollection\${FolderPath}"

        foreach ($collName in $CollectionNames) {
            if ($PSCmdlet.ShouldProcess($collName, "Move to folder")) {
                $coll = Get-CMDeviceCollection -Name $collName -ErrorAction Stop
                Move-CMObject -FolderPath $fullPath -InputObject $coll -ErrorAction Stop
                Write-Log -Message "Moved collection: $collName" -Level 'Info'
            }
        }

        Write-Log -Message "All collections moved to folder" -Level 'Success'
    }
}

#endregion

#region Main Execution

try {
    Write-Log -Message "========================================" -Level 'Info'
    Write-Log -Message "SCCM Application Deployment Script" -Level 'Info'
    Write-Log -Message "Application: $AppName" -Level 'Info'
    Write-Log -Message "Site: $SiteCode ($SiteServerFqdn)" -Level 'Info'
    Write-Log -Message "========================================" -Level 'Info'

    if ($WhatIf) {
        Write-Log -Message "Running in WhatIf mode - no changes will be made" -Level 'Warning'
    }

    # Verbose parameter logging
    if ($VerboseLogging -or $WhatIf) {
        Write-Log -Message "" -Level 'Info'
        Write-Log -Message "=== PARAMETER VALUES ===" -Level 'Info'
        Write-Log -Message "AppName: $AppName" -Level 'Info'
        Write-Log -Message "Description: $Description" -Level 'Info'
        Write-Log -Message "SiteCode: $SiteCode" -Level 'Info'
        Write-Log -Message "SiteServerFqdn: $SiteServerFqdn" -Level 'Info'
        Write-Log -Message "ContentLocation: $ContentLocation" -Level 'Info'
        Write-Log -Message "InstallCommand: $InstallCommand" -Level 'Info'
        Write-Log -Message "UninstallCommand: $UninstallCommand" -Level 'Info'
        Write-Log -Message "DeploymentTypeName: $DeploymentTypeName" -Level 'Info'
        Write-Log -Message "DPGroupName: $DPGroupName" -Level 'Info'
        Write-Log -Message "LimitingCollectionName: $LimitingCollectionName" -Level 'Info'
        Write-Log -Message "InstallCollectionName: $InstallCollectionName" -Level 'Info'
        Write-Log -Message "UninstallCollectionName: $UninstallCollectionName" -Level 'Info'
        Write-Log -Message "ApplicationFolder: $ApplicationFolder" -Level 'Info'
        Write-Log -Message "CollectionFolder: $CollectionFolder" -Level 'Info'
        Write-Log -Message "MaxRuntimeMins: $MaxRuntimeMins" -Level 'Info'
        Write-Log -Message "CollectionCreationTimeoutMinutes: $CollectionCreationTimeoutMinutes" -Level 'Info'
        Write-Log -Message "LogFilePath: $LogFilePath" -Level 'Info'
        Write-Log -Message "Force: $Force" -Level 'Info'
        Write-Log -Message "NoRollback: $NoRollback" -Level 'Info'
        Write-Log -Message "WhatIf: $WhatIf" -Level 'Info'
        Write-Log -Message "VerboseLogging: $VerboseLogging" -Level 'Info'
        Write-Log -Message "=======================" -Level 'Info'
        Write-Log -Message "" -Level 'Info'
    }

    # Pre-flight checks
    Test-Prerequisites

    # Initialize SCCM environment
    Initialize-SCCMEnvironment -SiteCode $SiteCode -SiteServer $SiteServerFqdn

    try {
        # Remove existing application if present
        if (-not $Force -and -not $WhatIf) {
            $existing = Get-CMApplication -Name $AppName -Fast -ErrorAction SilentlyContinue
            if ($existing) {
                $confirm = Read-Host "Application '$AppName' already exists. Remove and recreate? (Y/N)"
                if ($confirm -ne 'Y') {
                    throw "User cancelled operation"
                }
            }
        }

        Remove-ExistingApplication -Name $AppName

        # Create application with deployment type and detection
        New-ApplicationWithDetection `
            -Name $AppName `
            -Description $Description `
            -ContentPath $ContentLocation `
            -InstallCmd $InstallCommand `
            -UninstallCmd $UninstallCommand `
            -DeployTypeName $DeploymentTypeName `
            -MaxRuntime $MaxRuntimeMins

        # Set OS requirements
        Set-DeploymentTypeRequirements `
            -AppName $AppName `
            -DeployTypeName $DeploymentTypeName

        # Distribute content
        Start-ContentDistributionToDP `
            -AppName $AppName `
            -DPGroup $DPGroupName

        # Create device collections
        New-DeviceCollectionWithWait `
            -Name $InstallCollectionName `
            -LimiterName $LimitingCollectionName `
            -TimeoutMinutes $CollectionCreationTimeoutMinutes

        New-DeviceCollectionWithWait `
            -Name $UninstallCollectionName `
            -LimiterName $LimitingCollectionName `
            -TimeoutMinutes $CollectionCreationTimeoutMinutes

        # Create deployments
        New-ApplicationDeploymentWithWait `
            -AppName $AppName `
            -CollectionName $InstallCollectionName `
            -DeployAction Install `
            -DeployPurpose Required

        # Move to folders
        Move-ApplicationToFolder `
            -AppName $AppName `
            -FolderPath $ApplicationFolder `
            -SiteCode $SiteCode

        Move-CollectionsToFolder `
            -CollectionNames @($InstallCollectionName, $UninstallCollectionName) `
            -FolderPath $CollectionFolder `
            -SiteCode $SiteCode

        Write-Log -Message "========================================" -Level 'Success'
        Write-Log -Message "ALL STEPS COMPLETED SUCCESSFULLY" -Level 'Success'
        Write-Log -Message "Application: $AppName" -Level 'Success'
        Write-Log -Message "========================================" -Level 'Success'
    }
    catch {
        Write-Log -Message "Deployment failed: $_" -Level 'Error'

        if (-not $NoRollback -and $script:CreatedObjects.Application) {
            Invoke-Rollback
        }

        throw
    }
}
catch {
    Write-Log -Message "Script execution failed: $_" -Level 'Error'
    exit 1
}
finally {
    # Return to original location
    if ((Get-Location).Provider.Name -eq 'CMSite') {
        Pop-Location
    }

    if ($LogFilePath) {
        Write-Log -Message "Log file saved to: $LogFilePath" -Level 'Info'
    }
}

#endregion
