Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- Data ----------
$defaultSerials = ""
$allFolders     = @("conslog", "dqcomments", "mwdlog", "perflog", "quallog", "rigevent", "statlog")

# ---------- Shared state (thread-safe) ----------
$sync = [hashtable]::Synchronized(@{
    Log           = [System.Collections.ArrayList]::new()
    Progress      = 0
    ProgressMax   = 1
    Status        = ""
    Running       = $false
    Done          = $false
})

# ---------- Form ----------
$form              = New-Object System.Windows.Forms.Form
$form.Text         = "Reprocess to Live"
$form.Size         = New-Object System.Drawing.Size(720, 680)
$form.StartPosition = "CenterScreen"
$form.Font         = New-Object System.Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox  = $false

$y = 12

# --- Row 1: Year / Month / Source / Test Mode ---
$lblYear = New-Object System.Windows.Forms.Label
$lblYear.Text = "Year:"
$lblYear.Location = New-Object System.Drawing.Point(12, ($y + 3))
$lblYear.AutoSize = $true
$form.Controls.Add($lblYear)

$txtYear = New-Object System.Windows.Forms.TextBox
$txtYear.Text = (Get-Date).Year.ToString()
$txtYear.Location = New-Object System.Drawing.Point(50, $y)
$txtYear.Size = New-Object System.Drawing.Size(60, 24)
$form.Controls.Add($txtYear)

$lblMonth = New-Object System.Windows.Forms.Label
$lblMonth.Text = "Month:"
$lblMonth.Location = New-Object System.Drawing.Point(125, ($y + 3))
$lblMonth.AutoSize = $true
$form.Controls.Add($lblMonth)

$cboMonth = New-Object System.Windows.Forms.ComboBox
$cboMonth.DropDownStyle = "DropDownList"
$cboMonth.Location = New-Object System.Drawing.Point(178, $y)
$cboMonth.Size = New-Object System.Drawing.Size(52, 24)
1..12 | ForEach-Object { $cboMonth.Items.Add(("{0:D2}" -f $_)) } | Out-Null
$cboMonth.SelectedIndex = (Get-Date).Month - 1
$form.Controls.Add($cboMonth)

$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Text = "Source:"
$lblSource.Location = New-Object System.Drawing.Point(250, ($y + 3))
$lblSource.AutoSize = $true
$form.Controls.Add($lblSource)

$cboSource = New-Object System.Windows.Forms.ComboBox
$cboSource.DropDownStyle = "DropDownList"
$cboSource.Location = New-Object System.Drawing.Point(305, $y)
$cboSource.Size = New-Object System.Drawing.Size(80, 24)
$cboSource.Items.AddRange(@("Error", "Backup"))
$cboSource.SelectedIndex = 0
$form.Controls.Add($cboSource)

$chkTest = New-Object System.Windows.Forms.CheckBox
$chkTest.Text = "Test Mode (simulate only)"
$chkTest.Location = New-Object System.Drawing.Point(405, $y)
$chkTest.AutoSize = $true
$chkTest.Checked = $true
$form.Controls.Add($chkTest)

$y += 36

# --- Row 2: Drill Serials ---
$lblSerials = New-Object System.Windows.Forms.Label
$lblSerials.Text = "Drill Serials (separated by ;)"
$lblSerials.Location = New-Object System.Drawing.Point(12, $y)
$lblSerials.AutoSize = $true
$form.Controls.Add($lblSerials)

$y += 20

$txtSerials = New-Object System.Windows.Forms.TextBox
$txtSerials.Text = $defaultSerials
$txtSerials.Location = New-Object System.Drawing.Point(12, $y)
$txtSerials.Size = New-Object System.Drawing.Size(680, 24)
$form.Controls.Add($txtSerials)

# Set placeholder / cue banner text (shows when field is empty)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class CueBanner2 {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
    public static void Set(IntPtr handle, string text) { SendMessage(handle, 0x1501, IntPtr.Zero, text); }
}
"@
[CueBanner2]::Set($txtSerials.Handle, "Enter drill serials separated by ;  (e.g. 899201###1; 899201###2; 899201###3)")

$y += 32

# --- Row 3: Folder checkboxes ---
$grpFolders = New-Object System.Windows.Forms.GroupBox
$grpFolders.Text = "Folders"
$grpFolders.Location = New-Object System.Drawing.Point(12, $y)
$grpFolders.Size = New-Object System.Drawing.Size(680, 52)
$form.Controls.Add($grpFolders)

$chkAll = New-Object System.Windows.Forms.CheckBox
$chkAll.Text = "All"
$chkAll.Location = New-Object System.Drawing.Point(10, 20)
$chkAll.AutoSize = $true
$chkAll.Checked = $true
$grpFolders.Controls.Add($chkAll)

$folderChecks = @()
$fx = 60
foreach ($folder in $allFolders) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $folder
    $chk.Location = New-Object System.Drawing.Point($fx, 20)
    $chk.AutoSize = $true
    $chk.Checked = $true
    $grpFolders.Controls.Add($chk)
    $folderChecks += $chk
    $fx += 90
}

$chkAll.Add_CheckedChanged({
    foreach ($c in $folderChecks) { $c.Checked = $chkAll.Checked }
})

$y += 62

# --- Row 4: Buttons ---
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run"
$btnRun.Location = New-Object System.Drawing.Point(12, $y)
$btnRun.Size = New-Object System.Drawing.Size(90, 30)
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(40, 120, 40)
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = "Flat"
$form.Controls.Add($btnRun)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Clear Log"
$btnClear.Location = New-Object System.Drawing.Point(110, $y)
$btnClear.Size = New-Object System.Drawing.Size(80, 30)
$btnClear.FlatStyle = "Flat"
$form.Controls.Add($btnClear)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(200, ($y + 6))
$lblStatus.Size = New-Object System.Drawing.Size(480, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblStatus)

$y += 38

# --- Progress bar ---
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(12, $y)
$progressBar.Size = New-Object System.Drawing.Size(680, 18)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

$y += 26

# --- Log output ---
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(12, $y)
$txtLog.Size = New-Object System.Drawing.Size(680, ($form.ClientSize.Height - $y - 10))
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$form.Controls.Add($txtLog)

# ---------- Clear button ----------
$btnClear.Add_Click({ $txtLog.Clear() })

# ---------- UI poll timer (50 ms) ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50
$timer.Add_Tick({
    # Drain log queue
    while ($sync.Log.Count -gt 0) {
        $msg = $null
        try {
            $msg = $sync.Log[0]
            $sync.Log.RemoveAt(0)
        } catch { }
        if ($msg) {
            $txtLog.AppendText("$msg`r`n")
            $txtLog.ScrollToCaret()
        }
    }

    # Update progress bar
    if ($progressBar.Maximum -ne $sync.ProgressMax) {
        $progressBar.Maximum = [Math]::Max(1, $sync.ProgressMax)
    }
    $progressBar.Value = [Math]::Min($sync.Progress, $progressBar.Maximum)

    # Update status label
    if ($lblStatus.Text -ne $sync.Status -and $sync.Status) {
        $lblStatus.Text = $sync.Status
    }

    # Re-enable controls when worker signals done
    if ($sync.Done) {
        $sync.Done    = $false
        $sync.Running = $false
        $btnRun.Enabled     = $true
        $btnRun.Text        = "Run"
        $grpFolders.Enabled = $true
        $txtYear.Enabled    = $true
        $txtSerials.Enabled = $true
        $cboMonth.Enabled   = $true
        $cboSource.Enabled  = $true
        $chkTest.Enabled    = $true
    }
})
$timer.Start()

# ---------- Run button ----------
$btnRun.Add_Click({
    # Validate year
    if ($txtYear.Text -notmatch '^\d{4}$') {
        [System.Windows.Forms.MessageBox]::Show("Enter a valid 4-digit year.", "Validation", "OK", "Warning")
        return
    }

    # Gather selected folders
    $selectedFolders = @()
    for ($i = 0; $i -lt $folderChecks.Count; $i++) {
        if ($folderChecks[$i].Checked) { $selectedFolders += $allFolders[$i] }
    }
    if ($selectedFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one folder.", "Validation", "OK", "Warning")
        return
    }

    $year       = $txtYear.Text
    $month      = $cboMonth.SelectedItem.ToString()
    $sourceType = $cboSource.SelectedItem.ToString()
    $isTestMode = $chkTest.Checked
    $modeLabel  = if ($isTestMode) { "TEST" } else { "LIVE" }

    # Parse drill serials from textbox
    $serialNumbers = $txtSerials.Text -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    if ($serialNumbers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Enter at least one drill serial number.", "Validation", "OK", "Warning")
        return
    }

    # Admin check (warn, don't block)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin -and -not $isTestMode) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Not running as Administrator. File operations may fail.`nContinue?",
            "Warning", "YesNo", "Warning")
        if ($r -eq "No") { return }
    }

    # Confirmation dialog
    $folderList = $selectedFolders -join ", "
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Mode: $modeLabel`nPeriod: $year-$month`nSource: ServerDataRoot_$sourceType  ->  ServerDataRoot (Live)`nSerials: $($serialNumbers.Count)`nFolders: $folderList`n`nThis will move XML files into the LIVE server path.`nProceed?",
        "Confirm Reprocess to Live", "YesNo", "Warning")
    if ($r -eq "No") { return }

    # Lock UI controls
    $btnRun.Enabled     = $false
    $btnRun.Text        = "Running..."
    $grpFolders.Enabled = $false
    $txtYear.Enabled    = $false
    $txtSerials.Enabled = $false
    $cboMonth.Enabled   = $false
    $cboSource.Enabled  = $false
    $chkTest.Enabled    = $false
    $txtLog.Clear()

    # Reset shared state
    $sync.Log.Clear()
    $sync.Progress    = 0
    $sync.ProgressMax = $selectedFolders.Count * $serialNumbers.Count
    $sync.Status      = "Starting..."
    $sync.Running     = $true
    $sync.Done        = $false

    # ---------- Background runspace ----------
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("sync",            $sync)
    $rs.SessionStateProxy.SetVariable("serialNumbers",   $serialNumbers)
    $rs.SessionStateProxy.SetVariable("selectedFolders", $selectedFolders)
    $rs.SessionStateProxy.SetVariable("year",            $year)
    $rs.SessionStateProxy.SetVariable("month",           $month)
    $rs.SessionStateProxy.SetVariable("sourceType",      $sourceType)
    $rs.SessionStateProxy.SetVariable("isTestMode",      $isTestMode)
    $rs.SessionStateProxy.SetVariable("modeLabel",       $modeLabel)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({
        function SyncLog([string]$msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $sync.Log.Add("[$ts] $msg") | Out-Null
        }

        SyncLog "=== Starting $modeLabel reprocess to LIVE for $year-$month ==="
        SyncLog "Source: ServerDataRoot_$sourceType  ->  ServerDataRoot"
        SyncLog "Folders: $($selectedFolders -join ', ')"
        SyncLog ""

        $totalFiles    = 0
        $successCount  = 0
        $failedCount   = 0
        $skippedPaths  = 0
        $currentCombo  = 0
        $totalCombos   = $selectedFolders.Count * $serialNumbers.Count

        foreach ($folder in $selectedFolders) {
            foreach ($serial in $serialNumbers) {
                $currentCombo++
                $sync.Progress = $currentCombo
                $sync.Status   = "[$currentCombo / $totalCombos]  $serial | $folder"

                $sourcePath = "C:\ServerDataRoot_$sourceType\$serial\From Machine\prodout\$folder\$year-$month"
                $targetPath = "C:\ServerDataRoot\$serial\From Machine\prodout\$folder"

                if (-not (Test-Path -Path $sourcePath)) {
                    $skippedPaths++
                    continue
                }

                # Get all XML files recursively
                $files = Get-ChildItem -Path $sourcePath -Recurse -Filter "*.xml" -File
                if ($files.Count -eq 0) {
                    $skippedPaths++
                    continue
                }

                $totalFiles += $files.Count
                SyncLog "--- $serial | $folder  ($($files.Count) XML files) ---"

                # Ensure target directory exists
                if (-not (Test-Path -Path $targetPath)) {
                    try {
                        if (-not $isTestMode) {
                            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                            SyncLog "  Created: $targetPath"
                        } else {
                            SyncLog "  Would create: $targetPath"
                        }
                    } catch {
                        SyncLog "  FAILED to create: $targetPath - $_"
                        continue
                    }
                }

                # Move each file to the live target
                foreach ($file in $files) {
                    $destFile = Join-Path $targetPath $file.Name
                    try {
                        if (-not $isTestMode) {
                            Move-Item -Path $file.FullName -Destination $destFile -Force
                            $successCount++
                        } else {
                            SyncLog "    Move: $($file.Name)"
                        }
                    } catch {
                        $failedCount++
                        SyncLog "    FAILED move: $($file.Name) - $_"
                    }
                }
            }
        }

        # Summary
        SyncLog ""
        SyncLog "=========== SUMMARY ==========="
        SyncLog "Mode:               $modeLabel"
        SyncLog "Period:              $year-$month"
        SyncLog "Direction:           ServerDataRoot_$sourceType -> ServerDataRoot (Live)"
        SyncLog "Paths with files:    $($totalCombos - $skippedPaths) / $totalCombos"
        SyncLog "Total XML files:     $totalFiles"
        SyncLog "Successfully moved:  $successCount"
        SyncLog "Failed:              $failedCount"
        SyncLog "================================"

        $sync.Status = "Done - $totalFiles files processed"
        $sync.Done   = $true
    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
})

# ---------- Cleanup on close ----------
$form.Add_FormClosing({
    $timer.Stop()
    $timer.Dispose()
})

# ---------- Show ----------
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
