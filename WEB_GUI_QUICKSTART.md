# Web-Based GUI Quick Start

## 🌐 Much Better Than Windows Forms!

The web-based GUI eliminates the Windows Forms errors and provides a modern, beautiful interface.

---

## 🚀 Launch the GUI

### Step 1: Run the Script

```powershell
cd C:\Path\To\Scripts
.\Deploy-SCCMApplication-WebGUI.ps1
```

### Step 2: Browser Opens Automatically

The script will:
- Start a local web server on port 8080
- Automatically open your default browser
- Display the modern web interface

**URL:** `http://localhost:8080`

---

## 🎨 What You'll See

### Beautiful Modern Interface

- **Gradient purple header** with clear branding
- **Three tabs** for organized workflow:
  - ⚙️ Configuration - All deployment settings
  - 🔧 Options - Advanced settings
  - 📋 Execution Log - Real-time progress

- **Clean form layout** with validation
- **Real-time log viewer** (terminal-style: black background, green text)
- **Action buttons** at bottom:
  - 🧪 WhatIf (Test Run) - Blue button
  - 🚀 Deploy - Green button

---

## 📋 Configuration Tab

### Application Settings

| Field | Example | Required |
|-------|---------|----------|
| **Application Name** | `MyApp_v1.0` | ✅ Yes |
| **Deployment Type Name** | `MyApp_DEPLOY01` | No |
| **Description** | `Custom application` | No |
| **Site Code** | `365` | ✅ Yes |
| **Site Server FQDN** | `sccm.company.com` | ✅ Yes |

### Content Settings (Fieldset)

| Field | Example | Required |
|-------|---------|----------|
| **Content Location** | `\\server\apps\MyApp` | ✅ Yes |
| **Install Command** | `setup.exe /silent` | ✅ Yes |
| **Uninstall Command** | `uninstall.exe /quiet` | No |
| **Max Runtime** | `60` minutes | No |

### Collections & Distribution (Fieldset)

| Field | Example | Required |
|-------|---------|----------|
| **Limiting Collection** | `All Desktop and Server Clients` | ✅ Yes |
| **Install Collection** | *(auto-generated if empty)* | No |
| **Uninstall Collection** | *(auto-generated if empty)* | No |
| **DP Group** | `All Distribution Points` | ✅ Yes |

### Console Organization (Fieldset)

| Field | Example |
|-------|---------|
| **Application Folder** | `Desktops\3. PROD` |
| **Collection Folder** | `Desktops\Applications\3. PROD` |

---

## 🔧 Options Tab

### Logging Options

- ☑️ **Enable file logging** - Saves deployment log to file
- **Log File Path** - Custom path (or auto-generated in temp)

### Advanced Options

- ☐ **Force mode** - Skip confirmation prompts (for automation)
- ☐ **Disable rollback** - Don't auto-cleanup on failure
- **Collection Timeout** - Wait time for collection creation (default: 5 min)

---

## 📋 Execution Log Tab

### Real-Time Monitoring

- **Black terminal-style display** with green text
- **Auto-refreshing** (updates every second)
- **Status badge** shows current state:
  - 🟢 Ready
  - 🟡 Deploying... (with spinner)
  - 🟢 Success
  - 🔴 Error

### Log Controls

- **Clear Log** - Removes all log entries
- **Save Log** - Downloads log as text file
- **Refresh** - Manually update log display

---

## 🎯 Workflow

### Standard Deployment Workflow

1. **Configure** (Configuration tab)
   - Fill in application name
   - Set site code and server
   - Specify content location
   - Set install/uninstall commands

2. **Set Options** (Options tab)
   - Enable logging (recommended)
   - Set timeout if needed

3. **Test First** (Always recommended!)
   - Click **"🧪 WhatIf (Test Run)"**
   - Confirm the prompt
   - Auto-switches to Execution Log tab
   - Review output for errors

4. **Deploy** (If test passed)
   - Return to Configuration tab if changes needed
   - Click **"🚀 Deploy"**
   - Confirm warning prompt
   - Monitor progress in Execution Log

5. **Verify** (In SCCM Console)
   - Check application created
   - Verify content distribution
   - Confirm collections exist
   - Review deployment status

---

## ⚡ Key Features

### Real-Time Updates

- Log refreshes **every second** when on Log tab
- See deployment progress **as it happens**
- No manual refresh needed

### Input Validation

- **Required fields** marked with red asterisk (*)
- **UNC path validation** (must start with `\\`)
- **Helpful tooltips** under each field
- **Client-side validation** before submission

### Modern UX

- **Smooth animations** on tab switches
- **Hover effects** on buttons
- **Focus indicators** on inputs
- **Responsive design** (works on any screen size)

### No Installation Required

- **Just run the PowerShell script**
- **Browser opens automatically**
- **No dependencies** beyond PowerShell
- **No .NET Windows Forms issues**

---

## 🔧 Troubleshooting

### Port Already in Use

If port 8080 is already taken:

```powershell
.\Deploy-SCCMApplication-WebGUI.ps1 -Port 9090
```

Then open: `http://localhost:9090`

---

### Browser Doesn't Auto-Open

Manually navigate to:
```
http://localhost:8080
```

---

### Cannot Connect to Server

1. Check PowerShell console for errors
2. Verify script is still running
3. Check Windows Firewall settings
4. Try different port: `-Port 8081`

---

### Deployment Stuck

1. Check Execution Log tab for errors
2. Review file log (if enabled)
3. Stop server (Ctrl+C) and restart
4. Check SCCM console for partial objects

---

## 💡 Pro Tips

### Tip 1: Keep Server Running

- The PowerShell window must stay open
- Don't close it while browser is using the GUI
- Press **Ctrl+C** to stop server when done

### Tip 2: Multiple Browsers

You can open `http://localhost:8080` in multiple browser tabs/windows simultaneously.

### Tip 3: Bookmark It

Add `http://localhost:8080` to bookmarks for quick access (while server is running).

### Tip 4: Dark Mode Friendly

The log viewer uses dark theme (black background) which is easy on the eyes.

### Tip 5: Save Logs Automatically

Enable file logging in Options tab to keep permanent records of all deployments.

---

## 📊 Comparison: Web GUI vs Windows Forms

| Feature | Windows Forms | Web GUI |
|---------|---------------|---------|
| **Launch** | Direct .ps1 | Run server, opens browser |
| **Look & Feel** | Windows native | Modern gradient design |
| **Errors** | ❌ op_Substraction | ✅ No compatibility issues |
| **Customization** | Hard (C# needed) | Easy (just edit HTML/CSS) |
| **Updates** | Rebuild form | Just refresh browser |
| **Compatibility** | Windows only | Any modern browser |
| **Dependencies** | .NET Framework | None (just PowerShell) |
| **Log Viewer** | RichTextBox | Real-time web updates |
| **Mobile Friendly** | ❌ No | ✅ Yes (responsive) |

**Winner:** 🏆 **Web GUI** - Better in every way!

---

## 🎨 Customization

### Change Colors

Edit the `<style>` section in the script:

```css
/* Purple gradient - change to blue */
background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
/* Change to: */
background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
```

### Change Port

```powershell
.\Deploy-SCCMApplication-WebGUI.ps1 -Port 3000
```

### Add Custom Fields

Edit the HTML in `Get-HTMLPage` function - just add more form groups.

---

## 🔐 Security Notes

### Localhost Only

- Server binds to `localhost` only
- Not accessible from network
- Safe for local use

### No Authentication

- No login required
- Intended for single-user local deployments
- Don't expose to network without adding auth

---

## 📝 Example Session

```powershell
PS C:\Scripts> .\Deploy-SCCMApplication-WebGUI.ps1

=========================================
SCCM Deployment Web GUI Started
=========================================

Open your browser to: http://localhost:8080

Press Ctrl+C to stop the server
=========================================

# Browser opens automatically
# Fill in form fields
# Click "WhatIf (Test Run)"
# Review logs
# Click "Deploy"
# Watch real-time progress
# Verify in SCCM console
# Press Ctrl+C in PowerShell to stop server
```

---

## 🎓 Training Use

### Perfect for Training

The web GUI is **ideal for training** new SCCM admins:

1. **Visual Learning** - See all options clearly laid out
2. **Safe Testing** - WhatIf mode prevents mistakes
3. **Real-Time Feedback** - Watch what the script does
4. **No Scripting** - No PowerShell knowledge needed
5. **Repeatable** - Run multiple tests easily

### Training Workflow

1. Launch web GUI for each student
2. Walk through Configuration tab together
3. Let students fill in test values
4. Everyone runs WhatIf mode
5. Review logs together
6. Discuss what happened
7. Advanced students can try Deploy mode

---

## 📦 What Gets Created

Same as the command-line script:

1. ✅ SCCM Application
2. ✅ Deployment Type with detection rules
3. ✅ Content distribution to DPs
4. ✅ Install collection
5. ✅ Uninstall collection
6. ✅ Deployment to install collection
7. ✅ Organized in console folders

---

## 🆚 When to Use Each Interface

### Use Web GUI When:

- ✅ Manual, interactive deployments
- ✅ Training new administrators
- ✅ Testing configurations
- ✅ You want visual feedback
- ✅ One-off deployments

### Use Command-Line Script When:

- ✅ Automation/CI-CD pipelines
- ✅ Batch deployments
- ✅ Scheduled tasks
- ✅ Remote execution
- ✅ No GUI access

### Use Both:

- Web GUI for development/testing
- Script for production automation
- Same underlying engine, different interfaces

---

## 🎉 Advantages

### Why Web GUI Rocks

1. **No .NET Issues** - Pure HTML/CSS/JS
2. **Beautiful Design** - Modern gradient interface
3. **Easy Debugging** - F12 developer tools
4. **Customizable** - Edit HTML/CSS easily
5. **Responsive** - Works on tablets/phones
6. **Real-Time** - Live log updates
7. **Portable** - Any browser, any OS (with PowerShell)

---

## ✅ Quick Reference

```
╔════════════════════════════════════════════════════════╗
║       SCCM Web GUI - Quick Reference                  ║
╠════════════════════════════════════════════════════════╣
║                                                        ║
║  LAUNCH:                                               ║
║  .\Deploy-SCCMApplication-WebGUI.ps1                   ║
║                                                        ║
║  URL:                                                  ║
║  http://localhost:8080                                 ║
║                                                        ║
║  WORKFLOW:                                             ║
║  1. Fill Configuration tab                             ║
║  2. Set Options                                        ║
║  3. Click "WhatIf" to test                             ║
║  4. Review Execution Log                               ║
║  5. Click "Deploy" if test passed                      ║
║  6. Monitor progress                                   ║
║  7. Press Ctrl+C to stop server                        ║
║                                                        ║
║  REQUIRED FIELDS:                                      ║
║  • Application Name                                    ║
║  • Site Code                                           ║
║  • Site Server FQDN                                    ║
║  • Content Location (UNC)                              ║
║  • Install Command                                     ║
║  • Limiting Collection                                 ║
║  • Distribution Point Group                            ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
```

---

**Version:** 1.0
**Last Updated:** 2026-02-10
**Recommended:** ⭐⭐⭐⭐⭐ Use this instead of Windows Forms GUI!
