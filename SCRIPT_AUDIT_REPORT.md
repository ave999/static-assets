# PowerShell SCCM/MECM Application Deployment Script Audit Report

**Date:** 2026-02-10
**Script Purpose:** Automated SCCM application creation, deployment type configuration, content distribution, and collection management for Microsoft Project Standard 2024

---

## Executive Summary

**Overall Assessment:** MODERATE RISK - The script has several critical bugs that will cause runtime failures, along with security and maintainability concerns.

**Critical Issues Found:** 3
**High Priority Issues:** 5
**Medium Priority Issues:** 7
**Low Priority Issues:** 4

---

## CRITICAL ISSUES (Must Fix)

### 1. Invalid Parameter Syntax in Detection Clauses
**Location:** Lines with `New-CMDetectionClauseRegistryKeyValue`

```powershell
$cla1 = New-CMDetectionClauseRegistryKeyValue ... -Value
$cla2 = New-CMDetectionClauseRegistryKeyValue ... -Value
```

**Issue:** The `-Value` switch parameter is incorrectly placed at the end of the command. This syntax is invalid and will cause the cmdlet to fail or behave unexpectedly.

**Impact:** Detection rules may not be created correctly, causing the application deployment to fail or function improperly.

**Recommendation:** Remove the trailing `-Value` parameter or correct its usage based on the intended behavior.

---

### 2. Potentially Incorrect Detection Clause Connector Logic
**Location:** Add-CMScriptDeploymentType section

```powershell
-DetectionClauseConnector @(@{LogicalName=$logical1;Connector="and"},@{LogicalName=$logical2;Connector="and"})
```

**Issue:** The connector logic specifies "and" for both clauses, but the structure suggests this might be creating redundant or incorrect logic. Typically, you define connectors BETWEEN clauses, not FOR each clause.

**Impact:** Detection logic may not work as intended, causing false positives/negatives in application detection.

**Recommendation:** Review SCCM documentation for proper DetectionClauseConnector syntax. This parameter may be redundant when using GroupDetectionClauses.

---

### 3. Unused Configuration Variables
**Location:** Configuration section (lines ~60-62)

```powershell
$DetectionIs64Bit = $true
$DetectionIs64Bit2 = $true
```

**Issue:** These variables are defined but never used in the script. This suggests incomplete implementation or dead code.

**Impact:** May indicate missing 32-bit/64-bit registry redirection logic, potentially causing detection failures on some systems.

**Recommendation:** Either use these variables to configure detection clause registry view (32-bit vs 64-bit) or remove them.

---

## HIGH PRIORITY ISSUES

### 4. No Content Location Validation
**Location:** Before Start-CMContentDistribution

**Issue:** The script attempts to distribute content from `$ContentLocation` without verifying:
- Path exists
- Path is accessible from the provider
- Required files (InstallProjectSTD2024.cmd, RemoveProjectSTD2024.cmd) exist

**Impact:** Content distribution will fail, but only after the application and deployment type are already created, leaving an incomplete configuration.

**Recommendation:** Add `Test-Path` validation before content distribution step.

---

### 5. Insufficient Error Context for Collection Creation Failures
**Location:** Ensure-DeviceCollection function

**Issue:** If collection creation times out or fails, the error message is generic and doesn't provide actionable troubleshooting information.

**Impact:** Difficult to diagnose failures in production environments.

**Recommendation:** Add detailed logging about collection state, limiting collection status, and provider connection health.

---

### 6. Race Condition in Collection-to-Deployment Pipeline
**Location:** Between collection creation (step 8) and deployment creation (step 9)

**Issue:** While there's a 2-minute wait/retry loop after collection creation, there's no similar protection before attempting deployment. SCCM replication lag could cause deployment failures.

**Impact:** Script may fail intermittently in environments with replication delays.

**Recommendation:** Add similar wait/retry logic before New-CMApplicationDeployment.

---

### 7. Hard-Coded Paths and Configuration
**Location:** Throughout script (lines 27-62)

**Issue:** All configuration values are hard-coded constants rather than parameters. This makes the script:
- Non-reusable for other applications
- Difficult to integrate into CI/CD pipelines
- Prone to copy/paste errors when adapted

**Impact:** Maintenance overhead, increased error rate, limited reusability.

**Recommendation:** Convert all configuration values to script parameters with sensible defaults.

---

### 8. No Rollback Mechanism
**Location:** Overall script structure

**Issue:** If the script fails midway (e.g., during content distribution), partial changes remain:
- Application created but not functional
- Collections created but not deployed
- Incomplete deployment types

**Impact:** Requires manual cleanup, leaves SCCM in inconsistent state.

**Recommendation:** Implement try/catch with rollback logic or document manual cleanup procedures.

---

## MEDIUM PRIORITY ISSUES

### 9. Weak Site Drive Connection Logic
**Location:** Step 1 (Import module & connect)

```powershell
if (-not $cmDrive) { $cmDrive = (Get-PSDrive -PSProvider CMSITE | Select-Object -First 1).Name }
```

**Issue:** Falls back to first available CM site drive if the specific server isn't found. This could connect to the wrong site in multi-site environments.

**Impact:** Script could deploy to wrong SCCM site.

**Recommendation:** Fail explicitly if the specified site server isn't found.

---

### 10. Missing Module Path Validation
**Location:** Import-Module line

**Issue:** Assumes `$env:SMS_ADMIN_UI_PATH` exists and contains valid path.

**Impact:** Cryptic error if ConfigMgr console isn't installed or environment variable is missing.

**Recommendation:** Validate environment variable exists and path is valid before import attempt.

---

### 11. Inconsistent Error Handling Strategy
**Location:** Various Invoke-Step calls

**Issue:** Some steps use `-ContinueOnError` (line 96), most don't. No clear strategy for which failures are recoverable.

**Impact:** Unpredictable behavior on errors.

**Recommendation:** Document error handling strategy and consistently apply it.

---

### 12. Overly Generic Application Detection
**Location:** Get-CMApplication calls with -Fast parameter

**Issue:** Uses `-Fast` parameter which may not return complete object details needed for subsequent operations.

**Impact:** Potential issues if deployment depends on properties not returned by fast query.

**Recommendation:** Only use -Fast when genuinely needed for performance; otherwise use full query.

---

### 13. No Pre-Flight Validation
**Location:** Script start

**Issue:** Script doesn't validate prerequisites before starting:
- User has necessary SCCM permissions
- DP groups exist
- Limiting collections exist
- Required modules are available

**Impact:** Failures occur late in execution after partial changes.

**Recommendation:** Add comprehensive pre-flight validation section at start.

---

### 14. Silent Failure in Deployment Removal
**Location:** Step 2 (Remove existing deployments)

```powershell
$existingDeployments = Get-CMApplicationDeployment -Name $AppName -ErrorAction SilentlyContinue
```

**Issue:** Uses SilentlyContinue, which will hide actual errors (permissions, connectivity) not just "not found" situations.

**Impact:** Real errors are masked, making troubleshooting difficult.

**Recommendation:** Use try/catch with explicit handling for "not found" vs. other errors.

---

### 15. Timeout Value May Be Insufficient
**Location:** Ensure-DeviceCollection function (2-minute timeout)

**Issue:** 2-minute timeout for collection creation may be too short in large environments with slow replication or high database load.

**Impact:** Intermittent failures in busy environments.

**Recommendation:** Make timeout configurable or increase to 5 minutes.

---

## LOW PRIORITY ISSUES

### 16. No Logging to File
**Location:** Write-* functions

**Issue:** All output goes to console only. No persistent log file for audit trail.

**Impact:** Difficult to troubleshoot issues after the fact.

**Recommendation:** Add optional file logging with timestamps.

---

### 17. Variable Naming Inconsistencies
**Location:** Various

**Issue:** Mix of styles (e.g., `$AppName` vs. `$cmDrive`).

**Impact:** Slightly reduced readability.

**Recommendation:** Adopt consistent PascalCase or camelCase convention.

---

### 18. Comment Says "x64" But Includes ARM64
**Location:** Step 6 requirement rule

```powershell
# Add requirement for Windows 11 (x64) clients
...
PlatformString Windows/All_x64_Windows_11_and_higher_Clients, Windows/All_ARM64_Windows_11_and_higher_Clients
```

**Issue:** Comment is inaccurate/incomplete.

**Impact:** Confusion during code review or maintenance.

**Recommendation:** Update comment to reflect both architectures.

---

### 19. Verbose Output Not Consistently Used
**Location:** Various cmdlet calls

**Issue:** Some cmdlets use `-Verbose`, most don't. Inconsistent diagnostic output.

**Impact:** Variable troubleshooting information.

**Recommendation:** Standardize use of Verbose output or remove it entirely (use Write-Step instead).

---

## SECURITY CONSIDERATIONS

### 20. UNC Path Permissions Not Validated
**Issue:** Script assumes provider has read access to `\\eusdevptp3\SCCMSource\Applications\Defender` but doesn't validate.

**Recommendation:** Add Test-Path check or document required permissions.

---

### 21. No Audit Trail for Changes
**Issue:** Script makes significant SCCM changes without logging who ran it, when, or what was changed.

**Recommendation:** Add logging with username, timestamp, and change details to centralized log location.

---

### 22. Runs with Elevated Privileges
**Issue:** Requires SCCM Full Administrator rights but doesn't validate or document this.

**Recommendation:** Document required permissions and add checks for appropriate RBAC roles.

---

## BEST PRACTICE RECOMMENDATIONS

1. **Add CmdletBinding with SupportsShouldProcess** - Enable -WhatIf and -Confirm for safety
2. **Use Approved Verbs** - Functions use "Ensure-" which isn't approved; consider "Initialize-" or "New-"
3. **Add Comment-Based Help** - Include .SYNOPSIS, .DESCRIPTION, .EXAMPLE
4. **Implement Progress Indicators** - Use Write-Progress for long-running operations
5. **Add Pipeline Support** - Consider accepting input objects for batch processing
6. **Use Splatting Consistently** - Already used in some places ($dtParams), apply everywhere
7. **Implement Dry-Run Mode** - Allow validation without making changes
8. **Add Version Check** - Validate minimum ConfigMgr version for cmdlets used

---

## COMPLIANCE & STANDARDS

- **PowerShell Style Guide:** Partially compliant (some violations in naming, formatting)
- **Error Handling:** Good structure with Invoke-Step, but inconsistent application
- **Documentation:** Adequate inline comments, missing function help
- **Testability:** Difficult to unit test due to hard-coded dependencies

---

## TESTING RECOMMENDATIONS

1. Test in non-production environment with various failure scenarios:
   - Missing DP groups
   - Non-existent limiting collections
   - Inaccessible content paths
   - Replication delays
   - Insufficient permissions

2. Validate detection rules work correctly on target systems

3. Test with empty/new SCCM site and populated site

4. Verify behavior when script is run multiple times (idempotency)

---

## IMMEDIATE ACTION ITEMS

**Before running this script in production:**

1. ✅ Fix the `-Value` parameter syntax error (Critical #1)
2. ✅ Review and correct detection clause connector logic (Critical #2)
3. ✅ Add content location validation (High #4)
4. ✅ Address unused $DetectionIs64Bit variables (Critical #3)
5. ✅ Test detection rules manually to verify they work

---

## CONCLUSION

This script demonstrates good structure and error handling patterns but contains critical bugs that will prevent successful execution. The primary concerns are:

- **Syntax errors** in detection clause creation
- **Missing validation** for external dependencies
- **Hard-coded configuration** limiting reusability
- **Insufficient error recovery** leaving SCCM in inconsistent states

**Recommendation:** Do not run in production until critical issues are resolved and thoroughly tested in a development environment.

---

**Audited by:** Claude Code (Sonnet 4.5)
**Audit Type:** Static code analysis
**Scope:** Full script review including logic, security, best practices, and SCCM-specific considerations
