@echo off
:: Relaunch in a persistent cmd so the window NEVER closes before you can read it
if not "%~1"=="/wrapped" (
    cmd /k ""%~f0" /wrapped %*"
    exit /b
)
setlocal EnableDelayedExpansion
title hidi2c.sys Revert

:: ============================================================
:: hidi2c.sys Revert
:: Restores the .8972 backup if .1150 fails to load
:: Run from Safe Mode, as Administrator
:: Usage: hidi2c_REVERT.bat [/dryrun]
:: ============================================================

set "DRYRUN=0"
for %%a in (%*) do if /i "%%a"=="/dryrun" set "DRYRUN=1"
if "!DRYRUN!"=="1" echo *** DRY RUN - no changes will be made ***
echo.

:: Check admin
fltmc >nul 2>&1
if errorlevel 1 goto :FAIL_ADMIN

set TARGET_DIR=C:\Windows\System32\drivers
set DRIVERSTORE_DIR=C:\Windows\System32\DriverStore\FileRepository\hidi2c.inf_amd64_0e065a7c7db24746
set SYS_NAME=hidi2c.sys
set "BACKUP_DIR=%USERPROFILE%\Desktop\hidi2c_backups"

echo.
echo === hidi2c.sys Revert ===
echo.

:: Find the most recent backup
set LATEST=
for /f "delims=" %%f in ('dir /b /o-d "%BACKUP_DIR%\hidi2c.sys.*.bak" 2^>nul') do (
    if not defined LATEST set LATEST=%%f
)

if not defined LATEST goto :FAIL_NOBACKUP

echo Restoring: %LATEST%

if "!DRYRUN!"=="1" (
    echo   [dry-run] would takeown+icacls: %TARGET_DIR%\%SYS_NAME%
    echo   [dry-run] would del: %TARGET_DIR%\%SYS_NAME%
    echo   [dry-run] would copy: %BACKUP_DIR%\%LATEST% -> %TARGET_DIR%\%SYS_NAME%
    if exist "%DRIVERSTORE_DIR%\%SYS_NAME%" (
        echo   [dry-run] would takeown+icacls: %DRIVERSTORE_DIR%\%SYS_NAME%
        echo   [dry-run] would del: %DRIVERSTORE_DIR%\%SYS_NAME%
        echo   [dry-run] would copy: %BACKUP_DIR%\%LATEST% -> %DRIVERSTORE_DIR%\%SYS_NAME%
    )
    echo.
    echo *** DRY RUN COMPLETE - no changes were made ***
    goto :CLEARFLAG
)

echo   Restoring live driver copy...
takeown /f "%TARGET_DIR%\%SYS_NAME%" /a >nul 2>&1
icacls "%TARGET_DIR%\%SYS_NAME%" /grant administrators:F >nul 2>&1
del /f /q "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
copy /y "%BACKUP_DIR%\%LATEST%" "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
if errorlevel 1 goto :FAIL_LIVE

if exist "%DRIVERSTORE_DIR%\%SYS_NAME%" (
    echo   Restoring DriverStore copy...
    takeown /f "%DRIVERSTORE_DIR%\%SYS_NAME%" /a >nul 2>&1
    icacls "%DRIVERSTORE_DIR%\%SYS_NAME%" /grant administrators:F >nul 2>&1
    del /f /q "%DRIVERSTORE_DIR%\%SYS_NAME%" >nul 2>&1
    copy /y "%BACKUP_DIR%\%LATEST%" "%DRIVERSTORE_DIR%\%SYS_NAME%" >nul 2>&1
    if errorlevel 1 goto :FAIL_DRIVERSTORE
)

echo.
echo Reverted to %LATEST% - all copies verified.
echo Reboot to normal Windows.
goto :CLEARFLAG

:: ==================== FAILURE PATHS ====================

:FAIL_ADMIN
echo [ERROR] Must run as Administrator.
pause
goto :CLEARFLAG

:FAIL_NOBACKUP
echo [ERROR] No backup found in %BACKUP_DIR%
pause
goto :CLEARFLAG

:FAIL_LIVE
echo [ERROR] Failed to restore live driver.
pause
goto :CLEARFLAG

:FAIL_DRIVERSTORE
echo [ERROR] Failed to restore DriverStore copy. Live driver was restored.
echo On next boot, Windows may restore the new driver from DriverStore.
echo Re-run this script from Safe Mode.
pause
goto :CLEARFLAG

:CLEARFLAG
if "!DRYRUN!"=="1" (
    echo.
    echo [dry-run] would clear safeboot flag.
    echo.
    pause
    exit /b 0
)
echo.
echo Clearing safeboot flag so next boot is normal...
bcdedit /deletevalue {current} safeboot >nul 2>&1
if errorlevel 1 (
    echo   NOTE: safeboot flag not present or not cleared.
) else (
    echo   safeboot flag cleared.
)
echo.
pause
exit /b 0
