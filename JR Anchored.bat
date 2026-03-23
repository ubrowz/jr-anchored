@echo off
rem Double-click this file to launch JR Anchored.
rem It opens the graphical interface in your default browser.
rem
rem Requirements: Git for Windows must be installed and bash must be on PATH.

set "SCRIPT_DIR=%~dp0"
bash "%SCRIPT_DIR%bin/jr_app"
