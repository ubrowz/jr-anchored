@echo off
setlocal EnableDelayedExpansion

rem ---------------------------------------------------------------------------
rem  JR Anchored - Windows launcher
rem  Double-click to open the graphical interface in your default browser.
rem  Close this window to stop.
rem
rem  Requirements: R and Python installed (versions specified by your
rem  administrator). No Git for Windows required.
rem ---------------------------------------------------------------------------

rem --- Project root (filled in by admin during Export Configured App)
set "JRROOT="

rem --- Resolve project root
if not "!JRROOT!"=="" (
    set "PROJECT_ROOT=!JRROOT!"
) else (
    set "PROJECT_ROOT=%~dp0"
)
if "!PROJECT_ROOT:~-1!"=="\" set "PROJECT_ROOT=!PROJECT_ROOT:~0,-1!"

rem --- Find Python
set "PYTHON_BIN="
set "PY_VER_FILE=!PROJECT_ROOT!\admin\python_version.txt"

if exist "!PY_VER_FILE!" (
    for /f "tokens=1,2 delims=." %%A in ('type "!PY_VER_FILE!"') do (
        if "!PYTHON_BIN!"=="" (
            set "_CANDIDATE=%USERPROFILE%\AppData\Local\Programs\Python\Python%%A%%B\python.exe"
            if exist "!_CANDIDATE!" set "PYTHON_BIN=!_CANDIDATE!"
        )
    )
)

if "!PYTHON_BIN!"=="" (
    where python >nul 2>&1
    if !errorlevel!==0 (
        set "PYTHON_BIN=python"
    ) else (
        echo.
        echo  ERROR: Python was not found on this machine.
        echo  Please install Python ^(version specified by your administrator^) and try again.
        echo.
        pause
        exit /b 1
    )
)

rem --- Check / install Streamlit (pinned version, see admin\streamlit_version.txt)
set "STREAMLIT_SPEC=streamlit"
set "ST_PIN="
set "ST_VER_FILE=!PROJECT_ROOT!\admin\streamlit_version.txt"
if exist "!ST_VER_FILE!" (
    for /f "usebackq delims=" %%V in ("!ST_VER_FILE!") do (
        if "!STREAMLIT_SPEC!"=="streamlit" (
            set "ST_PIN=%%V"
            set "STREAMLIT_SPEC=streamlit==%%V"
        )
    )
)

"!PYTHON_BIN!" -c "import streamlit" >nul 2>&1
if !errorlevel! neq 0 (
    echo  Installing Streamlit ^(one-time setup, about 30 seconds^)...
    "!PYTHON_BIN!" -m pip install "!STREAMLIT_SPEC!" --quiet
    if !errorlevel! neq 0 (
        echo.
        echo  ERROR: Streamlit installation failed.
        echo  Check your internet connection and try again.
        echo.
        pause
        exit /b 1
    )
    echo  Streamlit installed.
    echo.
) else (
    rem Streamlit already present -- warn (but do not block) if its version differs
    rem from the pin. The idle watchdog uses a private Streamlit API, so a mismatched
    rem version may misbehave; the analysis path is unaffected (it runs via jrrun).
    if defined ST_PIN (
        set "ST_INSTALLED="
        for /f "usebackq delims=" %%I in (`"!PYTHON_BIN!" -c "import importlib.metadata as m; print(m.version('streamlit'))" 2^>nul`) do set "ST_INSTALLED=%%I"
        if defined ST_INSTALLED if /i not "!ST_INSTALLED!"=="!ST_PIN!" (
            echo  WARNING: Streamlit !ST_INSTALLED! is installed; this GUI was tested with !ST_PIN!.
            echo           Launching anyway -- your analysis results are unaffected: the GUI
            echo           only collects inputs, and all calculations run through the
            echo           validated jrrun path. If the interface looks wrong, you can
            echo           install the tested version with:
            echo             "!PYTHON_BIN!" -m pip install streamlit==!ST_PIN!
            echo.
        )
    )
)

rem --- Launch
set "APP_FILE=!PROJECT_ROOT!\app\jr_app.py"
set "PORT=8501"
set "URL=http://localhost:%PORT%"

echo.
echo  JR Anchored -- starting graphical interface...
echo  Opening %URL% in your browser.
echo  Close this window to stop.
echo.

rem Open browser after a short delay
start /b powershell -WindowStyle Hidden -Command "Start-Sleep -Seconds 2; Start-Process '%URL%'"

rem Launch Streamlit
"!PYTHON_BIN!" -m streamlit run "!APP_FILE!" ^
    --server.port %PORT% ^
    --server.address localhost ^
    --server.headless true ^
    --server.fileWatcherType none ^
    --browser.gatherUsageStats false ^
    --client.toolbarMode minimal ^
    --theme.primaryColor "#2E5BBA"

if !errorlevel! neq 0 (
    echo.
    echo  ERROR: The application exited unexpectedly ^(exit code !errorlevel!^).
    echo  Check the output above for details.
    echo.
    pause
)
