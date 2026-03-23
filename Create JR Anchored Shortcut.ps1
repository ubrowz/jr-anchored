# Create JR Anchored Shortcut
#
# Run this script once to create a desktop shortcut with the anchor icon.
# After creating it, you can pin the shortcut to the taskbar.
#
# Usage: right-click this file → "Run with PowerShell"

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$batFile    = Join-Path $scriptDir "JR Anchored.bat"
$iconFile   = Join-Path $scriptDir "JR Anchored.ico"
$desktop    = [Environment]::GetFolderPath("Desktop")
$shortcut   = Join-Path $desktop "JR Anchored.lnk"

$wsh  = New-Object -ComObject WScript.Shell
$lnk  = $wsh.CreateShortcut($shortcut)
$lnk.TargetPath      = $batFile
$lnk.WorkingDirectory = $scriptDir
$lnk.IconLocation    = "$iconFile,0"
$lnk.Description     = "Launch JR Anchored graphical interface"
$lnk.WindowStyle     = 1
$lnk.Save()

Write-Host ""
Write-Host "Shortcut created on your Desktop: JR Anchored.lnk"
Write-Host ""
Write-Host "To pin to the taskbar:"
Write-Host "  Right-click the shortcut on your Desktop"
Write-Host "  -> 'Pin to taskbar'"
Write-Host ""
