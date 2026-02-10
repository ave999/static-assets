# SCCM Application Deployment Tool - GUI User Guide

## Overview

The GUI front-end provides an easy-to-use interface for deploying SCCM applications without manually editing PowerShell parameters. It includes real-time log viewing, input validation, and test mode support.

![GUI Interface](https://img.shields.io/badge/Interface-Windows_Forms-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-green)

---

## Getting Started

### Prerequisites

1. **Windows System** with PowerShell 5.1 or later
2. **SCCM Console** installed on the machine
3. **Both script files** in the same folder:
   - `Deploy-SCCMApplication-GUI.ps1` (GUI launcher)
   - `Deploy-SCCMApplication-Improved.ps1` (deployment engine)

### Launching the GUI

**Option 1: Right-click method**
1. Right-click `Deploy-SCCMApplication-GUI.ps1`
2. Select **"Run with PowerShell"**

**Option 2: PowerShell console**
```powershell
cd "C:\Path\To\Scripts"
.\Deploy-SCCMApplication-GUI.ps1
```

**Option 3: From PowerShell ISE**
1. Open `Deploy-SCCMApplication-GUI.ps1` in PowerShell ISE
2. Press **F5** to run

---

## GUI Layout

### Three Main Tabs

1. **Configuration** - Set deployment parameters
2. **Options** - Configure logging and advanced options
3. **Execution Log** - View real-time deployment progress

### Action Buttons (Bottom)

- **WhatIf (Test Run)** - Simulates deployment without making changes
- **Deploy** - Executes actual deployment
- **Close** - Exits the GUI

---

## Configuration Tab

### Basic Settings

| Field | Description | Example | Required |
|-------|-------------|---------|----------|
| **Application Name** | Name of the app in SCCM | `MSCPPROJECTSTD_2024_00S00_P` | ✅ Yes |
| **Description** | App description | `Microsoft Project Standard 2024` | ✅ Yes |
| **Site Code** | 3-letter SCCM site code | `365` | ✅ Yes |
| **Site Server FQDN** | Site server hostname | `sccm.domain.com` | ✅ Yes |

### Content Settings

| Field | Description | Example | Required |
|-------|-------------|---------|----------|
| **Content Location (UNC)** | Network path to files | `\\server\apps\Project2024` | ✅ Yes |
| **Install Command** | Installation executable | `setup.exe /silent` | ✅ Yes |
| **Uninstall Command** | Uninstall executable | `uninstall.exe /quiet` | ⚠️ Optional |
| **Deployment Type Name** | DT identifier | `Project2024_DEPLOY01` | ✅ Yes |
| **Max Runtime** | Minutes (1-720) | `60` | ✅ Yes |

**💡 Tip:** Click the **"..."** button next to Content Location to browse for folders.

### Collections Settings

| Field | Description | Default Behavior | Required |
|-------|-------------|------------------|----------|
| **Limiting Collection** | Parent collection | - | ✅ Yes |
| **Install Collection** | Target devices | Uses Application Name if empty | ⚠️ Optional |
| **Uninstall Collection** | Uninstall targets | Uses AppName + "_Uninstall" | ⚠️ Optional |

**💡 Tip:** Leave Install/Uninstall collections blank to auto-generate names.

### Distribution & Organization

| Field | Description | Example | Required |
|-------|-------------|---------|----------|
| **Distribution Point Group** | DP group for content | `All Distribution Points` | ✅ Yes |
| **Application Folder Path** | Console folder location | `Desktops\3. PROD` | ✅ Yes |
| **Collection Folder Path** | Collections folder | `Desktops\Applications\3. PROD` | ✅ Yes |

---

## Options Tab

### Logging Options

**Enable file logging** ☑️
- When checked, saves detailed log to file
- Useful for audit trail and troubleshooting
- Default location: `%TEMP%\SCCM-Deploy-[timestamp].log`

**💡 Tip:** Click **"..."** to choose custom log location.

### Advanced Options

| Option | Description | Default | When to Use |
|--------|-------------|---------|-------------|
| **Force mode** | Skip confirmation prompts | ❌ Off | Automated/CI-CD scripts |
| **Disable rollback** | Don't undo on failure | ❌ Off | Troubleshooting/debugging |
| **Collection Timeout** | Wait time (1-30 min) | 5 min | Slow replication environments |

---

## Execution Log Tab

### Features

- **Real-time output** - See progress as deployment runs
- **Color-coded** - Black background with green text for readability
- **Scrolling** - Auto-scrolls to latest output
- **Persistent** - Log remains after completion

### Buttons

**Clear Log**
- Clears the current log display
- Useful when running multiple deployments

**Save Log**
- Exports log to text file
- Includes full session history
- Useful for documentation

---

## Using the GUI

### Workflow: Test Deployment (Recommended First Step)

1. **Fill out Configuration tab** with your app details
2. **Review Options tab** settings
3. Click **"WhatIf (Test Run)"**
4. Confirm when prompted
5. **Switch to Execution Log tab** to watch progress
6. Review output for any validation errors
7. If successful, proceed with actual deployment

### Workflow: Actual Deployment

1. After successful WhatIf test
2. Return to **Configuration tab** if changes needed
3. Click **"Deploy"**
4. Confirm the warning prompt
5. **Monitor Execution Log tab**
6. Wait for completion message
7. Verify in SCCM console

### Workflow: Saving Configuration for Later

Currently, the GUI doesn't save settings between runs. To save your configuration:

1. Take a screenshot of the Configuration tab
2. Or manually note the values
3. Or edit the default values in the script file

---

## Validation & Error Handling

### Automatic Validation

The GUI validates inputs before running:

✅ **Checks for:**
- Empty required fields
- Valid UNC path format (must start with `\\`)
- Numeric ranges (timeouts, runtimes)

❌ **Common Validation Errors:**

| Error | Solution |
|-------|----------|
| "Application Name is required" | Enter an app name |
| "Must be valid UNC path" | Use format: `\\server\share\folder` |
| "Content Location is required" | Fill in the UNC path field |
| "Site Code is required" | Enter 3-letter site code |

### Script Execution Errors

If deployment fails:

1. **Check Execution Log tab** for error details
2. **Review file log** (if enabled) for full stack trace
3. **Verify prerequisites**:
   - SCCM console installed
   - Access to site server
   - Network path accessible
   - Permissions granted

---

## Common Scenarios

### Scenario 1: Deploy New Application (First Time)

```
1. Launch GUI
2. Configuration Tab:
   - Application Name: "MyApp_v1.0"
   - Site Code: "ABC"
   - Site Server: "sccm.company.com"
   - Content Location: "\\fileserver\apps\MyApp"
   - Install Command: "setup.exe /s"
   - Uninstall: "uninstall.exe /s"
   - Leave collections blank (auto-generated)
3. Options Tab:
   - ✅ Enable file logging
   - Log Path: (use default)
4. Click "WhatIf (Test Run)"
5. Review log for issues
6. If OK, click "Deploy"
7. Verify in SCCM console
```

**Expected Time:** 5-10 minutes

---

### Scenario 2: Update Existing Application

```
1. Launch GUI
2. Configuration Tab:
   - Application Name: Use SAME name as existing app
   - Update version in content location
   - Update install/uninstall commands if changed
3. Options Tab:
   - ✅ Force mode (to skip overwrite prompt)
4. Click "Deploy"
5. Confirm overwrite
```

**Note:** Script will remove old app and deploy new one.

---

### Scenario 3: Deploy to Different Site

```
1. Launch GUI
2. Configuration Tab:
   - Change "Site Code" to target site
   - Change "Site Server FQDN" to target server
   - Verify content path is accessible from target site
3. Continue normally
```

---

### Scenario 4: Test Mode for Training

```
1. Perfect for training new admins
2. Use WhatIf mode repeatedly
3. Change parameters and retest
4. No risk of breaking production
5. Review logs to understand process
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Tab` | Navigate between fields |
| `Shift+Tab` | Navigate backwards |
| `Ctrl+Tab` | Switch to next tab |
| `Ctrl+Shift+Tab` | Switch to previous tab |
| `Alt+W` | Click WhatIf button |
| `Alt+D` | Click Deploy button |
| `Esc` | Close GUI |

---

## Troubleshooting

### GUI Won't Launch

**Error:** "Execution policy"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Error:** "Cannot load assembly"
- Your Windows installation may be missing .NET Framework
- Install .NET Framework 4.7.2 or later

---

### Script Not Found Error

**Error:** "Could not find Deploy-SCCMApplication-Improved.ps1"

**Solution:**
```powershell
# Ensure both files are in same folder
Get-ChildItem Deploy-*.ps1
```

Expected output:
```
Deploy-SCCMApplication-Improved.ps1
Deploy-SCCMApplication-GUI.ps1
```

---

### Content Location Not Accessible

**Error:** "Content location not accessible"

**Checklist:**
- [ ] UNC path format: `\\server\share\folder`
- [ ] Network connectivity to server
- [ ] Share permissions granted
- [ ] Files exist in path
- [ ] Install command file exists

**Test manually:**
```powershell
Test-Path "\\server\share\folder\setup.exe"
```

---

### Collection Creation Timeout

**Error:** "Collection creation timed out"

**Solutions:**
1. Increase timeout in Options tab (try 10 minutes)
2. Check SCCM site server performance
3. Verify limiting collection exists
4. Check SCCM console for replication issues

---

### Application Already Exists

**Behavior:** Prompt asking to overwrite

**Options:**
1. Click "Yes" to remove and recreate
2. Click "No" to cancel
3. Enable "Force mode" in Options to skip prompt

---

## Tips & Best Practices

### 🎯 Best Practices

1. **Always test with WhatIf first**
   - Catches configuration errors
   - Validates prerequisites
   - No risk to production

2. **Enable logging for production deployments**
   - Required for compliance
   - Helps troubleshooting
   - Documents changes

3. **Use descriptive application names**
   - Include version number
   - Include architecture (x64/x86)
   - Example: `Office2024_x64_v16.0`

4. **Verify content path accessibility**
   - Test manually before deploying
   - Check from site server perspective
   - Ensure SCCM provider can read

5. **Don't force mode unless necessary**
   - Confirmation prompts prevent mistakes
   - Only use for automation

### 💡 Pro Tips

**Tip 1: Quick Redeploy**
- Keep GUI open
- Change just the version number
- Click Deploy again
- Saves time for iterative testing

**Tip 2: Log File Naming**
```
Format: AppName-SiteCode-YYYYMMDD-HHMMSS.log
Example: Project2024-365-20260210-143022.log
```

**Tip 3: Test in Dev First**
- Change Site Code/Server to dev environment
- Test full deployment
- Then switch to production settings

**Tip 4: Monitor Content Distribution**
- After deployment, check SCCM console
- Monitoring > Distribution Status
- Ensure content reaches all DPs

---

## Integration with CI/CD

While the GUI is interactive, you can still automate using the underlying script:

```powershell
# In Azure DevOps, Jenkins, etc.
.\Deploy-SCCMApplication-Improved.ps1 `
    -AppName "MyApp_v1.0" `
    -SiteCode "PRD" `
    -SiteServerFqdn "sccm.company.com" `
    -ContentLocation "\\fileserver\apps\MyApp" `
    -InstallCommand "setup.exe /s" `
    -Force `
    -Confirm:$false `
    -LogFilePath "C:\Logs\automated-deploy.log"
```

**GUI is for:** Manual, interactive deployments
**Script is for:** Automated, unattended deployments

---

## Advanced: Customizing the GUI

### Changing Default Values

Edit `Deploy-SCCMApplication-GUI.ps1` and find these lines:

```powershell
$txtSiteCode.Text = '365'          # Change default site code
$txtSiteServer.Text = 'sccm.com'   # Change default server
$numMaxRuntime.Value = 60          # Change default runtime
```

### Adding Custom Validation

Find the `Invoke-Validation` function and add rules:

```powershell
if ($txtAppName.Text -notmatch '^[A-Z]') {
    $errors += "Application Name must start with uppercase letter"
}
```

### Changing Colors/Theme

```powershell
# Change log colors
$rtbLog.BackColor = [System.Drawing.Color]::DarkBlue
$rtbLog.ForeColor = [System.Drawing.Color]::White

# Change button colors
$btnDeploy.BackColor = [System.Drawing.Color]::Green
```

---

## Frequently Asked Questions

**Q: Can I deploy to multiple sites at once?**
A: No, deploy to one site at a time. Run the GUI multiple times for different sites.

**Q: Does the GUI require internet access?**
A: No, it's fully offline. Only requires network access to your SCCM server and content location.

**Q: Can I save my configuration as a template?**
A: Not built-in, but you can create multiple copies of the script with different defaults.

**Q: What happens if I close the GUI during deployment?**
A: The deployment script continues running in background. Check SCCM console or log file.

**Q: Can I deploy to user collections?**
A: Current version only supports device collections. Modify the script for user collections.

**Q: Does this work with SCCM 2012?**
A: Designed for Current Branch (1902+). May work on 2012 R2 but not tested.

---

## Support & Feedback

### Getting Help

1. **Check Execution Log** - Most errors are clearly explained
2. **Review file log** - More detailed than GUI log
3. **Check SCCM console** - Verify objects were created
4. **Review audit report** - `SCRIPT_AUDIT_REPORT.md` for known issues

### Reporting Issues

When reporting issues, include:
- [ ] Screenshot of Configuration tab
- [ ] Screenshot of error message
- [ ] Contents of Execution Log
- [ ] File log (if enabled)
- [ ] SCCM version and build number

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-10 | Initial release with full GUI support |

---

## Related Files

- **Deploy-SCCMApplication-Improved.ps1** - Core deployment engine
- **SCRIPT_AUDIT_REPORT.md** - Original audit findings
- **IMPROVEMENTS_SUMMARY.md** - List of improvements made
- **GUI_USER_GUIDE.md** - This document

---

## Quick Reference Card

```
╔════════════════════════════════════════════════════════════╗
║     SCCM Application Deployment Tool - Quick Reference     ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  REQUIRED FIELDS:                                          ║
║  • Application Name                                        ║
║  • Site Code (3 letters)                                   ║
║  • Site Server FQDN                                        ║
║  • Content Location (UNC: \\server\share)                  ║
║  • Install Command                                         ║
║  • Distribution Point Group                                ║
║  • Limiting Collection                                     ║
║                                                            ║
║  WORKFLOW:                                                 ║
║  1. Fill Configuration tab                                 ║
║  2. Set Options (logging, force, etc.)                     ║
║  3. Click "WhatIf" to test                                 ║
║  4. Review Execution Log                                   ║
║  5. Click "Deploy" if test passed                          ║
║  6. Verify in SCCM console                                 ║
║                                                            ║
║  BUTTONS:                                                  ║
║  • WhatIf = Test run (no changes)                          ║
║  • Deploy = Execute deployment                             ║
║  • Close = Exit GUI                                        ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

---

**Document Version:** 1.0
**Last Updated:** 2026-02-10
**Compatibility:** PowerShell 5.1+, Windows 10/11, Windows Server 2016+
