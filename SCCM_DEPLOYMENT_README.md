# SCCM Application Deployment Toolkit

A production-ready PowerShell toolkit for automated SCCM (Microsoft Endpoint Configuration Manager) application deployment with GUI front-end.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)
[![SCCM](https://img.shields.io/badge/SCCM-Current_Branch-green.svg)](https://docs.microsoft.com/en-us/mem/configmgr/)

---

## 📋 Overview

This toolkit provides enterprise-grade automation for SCCM application deployments with:

- ✅ **Windows Forms GUI** - User-friendly interface for non-scripters
- ✅ **Production-Ready Script** - Robust PowerShell deployment engine
- ✅ **Comprehensive Validation** - Pre-flight checks prevent errors
- ✅ **Rollback Capability** - Automatic cleanup on failure
- ✅ **Real-time Logging** - Track progress and troubleshoot issues
- ✅ **WhatIf Mode** - Test deployments without making changes

---

## 🚀 Quick Start

### Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- SCCM Console installed
- Appropriate SCCM permissions (Full Administrator or Application Administrator)

### Installation

1. **Download all files** to a folder:
   ```
   C:\Scripts\SCCM-Deploy\
   ├── Deploy-SCCMApplication-GUI.ps1
   ├── Deploy-SCCMApplication-Improved.ps1
   ├── GUI_USER_GUIDE.md
   └── SCCM_DEPLOYMENT_README.md
   ```

2. **Set execution policy** (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **Launch the GUI**:
   ```powershell
   cd C:\Scripts\SCCM-Deploy
   .\Deploy-SCCMApplication-GUI.ps1
   ```

### First Deployment (GUI Method)

1. **Fill Configuration Tab**:
   - Application Name: `MyApp_v1.0`
   - Site Code: Your 3-letter site code
   - Site Server: Your SCCM server FQDN
   - Content Location: UNC path to app files

2. **Enable Logging** (Options Tab):
   - ☑️ Enable file logging

3. **Test First**:
   - Click **"WhatIf (Test Run)"**
   - Review log output

4. **Deploy**:
   - Click **"Deploy"**
   - Confirm and monitor progress

---

## 📁 File Descriptions

| File | Purpose | When to Use |
|------|---------|-------------|
| **Deploy-SCCMApplication-GUI.ps1** | Windows Forms interface | Manual, interactive deployments |
| **Deploy-SCCMApplication-Improved.ps1** | Core deployment engine | Automation, CI/CD, advanced usage |
| **GUI_USER_GUIDE.md** | Complete GUI documentation | Learning to use the GUI |
| **SCRIPT_AUDIT_REPORT.md** | Original security audit | Understanding issues fixed |
| **IMPROVEMENTS_SUMMARY.md** | List of all improvements | Technical details of changes |

---

## 🎯 Usage Examples

### Example 1: Deploy with GUI (Recommended)

```powershell
# Launch GUI
.\Deploy-SCCMApplication-GUI.ps1

# Then use visual interface to:
# 1. Configure deployment
# 2. Test with WhatIf
# 3. Deploy
```

**Best for:** Manual deployments, learning, testing

---

### Example 2: Deploy with Script (Command Line)

```powershell
.\Deploy-SCCMApplication-Improved.ps1 `
    -AppName "Office2024_x64" `
    -SiteCode "ABC" `
    -SiteServerFqdn "sccm.company.com" `
    -ContentLocation "\\fileserver\apps\Office2024" `
    -InstallCommand "setup.exe /configure config.xml" `
    -UninstallCommand "setup.exe /configure uninstall.xml" `
    -LogFilePath "C:\Logs\office-deploy.log"
```

**Best for:** Automation, scripting, CI/CD pipelines

---

## 🔧 Key Features

### GUI Features

- **Tab-Based Interface** - Organized configuration sections
- **Input Validation** - Prevents common errors
- **Real-Time Log Viewer** - Watch deployment progress
- **Test Mode** - WhatIf support with one click
- **Log Export** - Save session logs for documentation
- **Browse Dialogs** - Easy file/folder selection

### Script Features

- **Parameterized** - All values configurable
- **Pre-Flight Validation** - Checks prerequisites before deployment
- **Rollback Mechanism** - Automatic cleanup on failure
- **Retry Logic** - Handles replication delays
- **File Logging** - Detailed audit trail
- **Comment-Based Help** - Full documentation via `Get-Help`

---

## 📚 Documentation

- **[GUI User Guide](GUI_USER_GUIDE.md)** - Complete GUI documentation
- **[Improvements Summary](IMPROVEMENTS_SUMMARY.md)** - Technical details of all enhancements
- **[Audit Report](SCRIPT_AUDIT_REPORT.md)** - Original security audit findings

### Built-In Help

```powershell
# Get full script documentation
Get-Help .\Deploy-SCCMApplication-Improved.ps1 -Full

# Get examples
Get-Help .\Deploy-SCCMApplication-Improved.ps1 -Examples
```

---

## 🎯 Comparison with Original Script

| Feature | Original | Improved + GUI |
|---------|----------|----------------|
| **Interface** | ❌ None | ✅ Windows Forms GUI |
| **Syntax Errors** | ❌ Critical bugs | ✅ All fixed |
| **Validation** | ❌ None | ✅ Comprehensive |
| **Rollback** | ❌ Manual | ✅ Automatic |
| **Logging** | ⚠️ Console only | ✅ File + Real-time GUI |
| **Testing** | ❌ No WhatIf | ✅ Full WhatIf support |
| **Parameterization** | ❌ Hard-coded | ✅ Fully parameterized |
| **Documentation** | ⚠️ Inline only | ✅ Full help + guides |
| **Production Ready** | ❌ No | ✅ Yes |

---

**Made with ❤️ for SCCM Administrators**

```
╔════════════════════════════════════════════════════════╗
║  SCCM Application Deployment Toolkit                  ║
║  Version 2.0 - Production Ready                        ║
║                                                        ║
║  ✅ GUI Interface    ✅ Auto Rollback                  ║
║  ✅ Validation       ✅ File Logging                   ║
║  ✅ WhatIf Mode      ✅ Full Documentation             ║
╚════════════════════════════════════════════════════════╝
```
