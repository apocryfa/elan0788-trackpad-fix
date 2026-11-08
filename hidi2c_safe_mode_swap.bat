@echo off
:: Relaunch in a persistent cmd so the window NEVER closes before you can read it
if not "%~1"=="/wrapped" (
    cmd /k ""%~f0" /wrapped %*"
    exit /b
)
setlocal EnableDelayedExpansion
title hidi2c.sys Safe-Mode Driver Swap

:: ============================================================
:: hidi2c.sys Safe-Mode Driver Swap
:: Replaces live .8972 with pre-regression .1150 (Valid-signed)
:: MUST be run from Safe Mode (hidi2c unloaded, file writable)
:: NOTE: trackpad does NOT work in Safe Mode - use the keyboard
:: Usage: hidi2c_safe_mode_swap.bat [/dryrun]
:: ============================================================

set "DRYRUN=0"
for %%a in (%*) do if /i "%%a"=="/dryrun" set "DRYRUN=1"
set "LOG=%USERPROFILE%\Desktop\hidi2c_swap_log.txt"
>>"%LOG%" echo ==== run start (dryrun=!DRYRUN!) %date% %time% ====
if "!DRYRUN!"=="1" echo *** DRY RUN - no changes will be made ***
echo.

:: Check admin (fltmc works in Safe Mode, unlike net session)
fltmc >nul 2>&1
if errorlevel 1 goto :FAIL_ADMIN

:: Check safe mode
reg query "HKLM\SYSTEM\CurrentControlSet\Control\SafeBoot\Option" /v OptionValue >nul 2>&1
if not errorlevel 1 goto :SAFE_MODE_OK
echo [WARNING] Not in Safe Mode. The file may be locked.
echo Recommended: Reboot into Safe Mode first.
echo   Shift+Restart, then Troubleshoot, Advanced, Startup Settings, Restart, F4
echo   (F4 = Safe Mode MINIMAL - hidi2c will not be loaded, so the file is writable)
echo.
if "!DRYRUN!"=="1" goto :SAFE_MODE_OK
set /p CONTINUE="Continue anyway? (y/N): "
if /i not "!CONTINUE!"=="y" goto :CLEARFLAG

:SAFE_MODE_OK
set "SRC_DIR=%~dp0"
set "SRC_DIR=%SRC_DIR:~0,-1%"
set TARGET_DIR=C:\Windows\System32\drivers
set DRIVERSTORE_DIR=C:\Windows\System32\DriverStore\FileRepository\hidi2c.inf_amd64_0e065a7c7db24746
set SYS_NAME=hidi2c.sys
set NEW_SYS=hidi2c-1150.sys
set NEW_INF=hidi2c_1150.inf
set NEW_CAT=hidi2c_26100.1_catalog.cat
set "BACKUP_DIR=%USERPROFILE%\Desktop\hidi2c_backups"
set "DEVICE_ID=ACPI\ELAN0788\4&18EA2290&0"
set "DEVICE_DISABLED=0"
set FALLBACK_BAK=%SRC_DIR%\hidi2c_26100.8972.backup.sys

echo.
echo === hidi2c.sys Safe-Mode Driver Swap ===
echo.

:: Verify source files exist
if not exist "%SRC_DIR%\%NEW_SYS%" goto :FAIL_SRC_SYS

:: Verify signature BEFORE anything else
echo [1/6] Verifying signature of %NEW_SYS% ...
powershell -NoProfile -Command "if ((Get-AuthenticodeSignature '%SRC_DIR%\%NEW_SYS%').Status -ne 'Valid') { exit 1 }"
if errorlevel 1 goto :FAIL_SIG
echo   Signature: Valid
>>"%LOG%" echo [OK] signature Valid

:: Back up current file (NON-FATAL - fallback .8972 exists in Downloads)
echo [2/6] Backing up current hidi2c.sys ...
set "BACKUP_NAME=hidi2c.sys.before-swap.bak"
set BACKUP_OK=0
if "!DRYRUN!"=="1" goto :DRYRUN_BACKUP
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
>>"%LOG%" echo [step] 2a backup copy starting
copy /y "%TARGET_DIR%\%SYS_NAME%" "%BACKUP_DIR%\%BACKUP_NAME%" >nul 2>&1
if errorlevel 1 goto :BACKUP_FAILED
set BACKUP_OK=1
echo   Backup: %BACKUP_DIR%\%BACKUP_NAME%
>>"%LOG%" echo [OK] backup created
goto :BACKUP_DONE
:BACKUP_FAILED
echo   WARN: backup copy failed (file locked - use Safe Mode MINIMAL, F4).
>>"%LOG%" echo [WARN] backup copy failed
echo   WARN: Live backup failed. Fallback available: %FALLBACK_BAK%
if exist "%FALLBACK_BAK%" goto :BACKUP_FALLBACK_OK
echo   ERROR: No fallback. Reboot into Safe Mode (minimal) where hidi2c is NOT loaded.
pause
goto :NO_FALLBACK
:BACKUP_FALLBACK_OK
echo   Fallback .8972 found in Downloads - swap can proceed.
echo   (Revert would use the fallback, not a live backup.)
:BACKUP_DONE
>>"%LOG%" echo [step] 2/6 backup block done, BACKUP_OK=!BACKUP_OK!

goto :MANUAL
:DRYRUN_BACKUP
echo   [dry-run] would copy: %TARGET_DIR%\%SYS_NAME% to %BACKUP_DIR%\%BACKUP_NAME%
set BACKUP_OK=1
:MANUAL
:: Manual file replacement (pnputil cannot bind - INF HardwareId mismatch)
echo [3/6] Manual replacement (pnputil skipped - INF does not match device)...
echo [4/6] Taking ownership of %SYS_NAME% ...
echo [5/6] Installing .1150 driver...
if "!DRYRUN!"=="1" goto :DRYRUN_MANUAL
echo   Taking ownership...
takeown /f "%TARGET_DIR%\%SYS_NAME%" /a >nul 2>&1
icacls "%TARGET_DIR%\%SYS_NAME%" /grant administrators:F >nul 2>&1

if exist "%DRIVERSTORE_DIR%\%SYS_NAME%" (
    takeown /f "%DRIVERSTORE_DIR%\%SYS_NAME%" /a >nul 2>&1
    icacls "%DRIVERSTORE_DIR%\%SYS_NAME%" /grant administrators:F >nul 2>&1
)

echo   Deleting old driver files...
del /f /q "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
if exist "%TARGET_DIR%\%SYS_NAME%" goto :UNLOAD_DRIVER
goto :DELETE_DONE

:UNLOAD_DRIVER
echo   [WARN] %SYS_NAME% still present - driver is loaded, file is locked.
>>"%LOG%" echo [WARN] delete failed - file locked by loaded driver
echo   Disabling the ELAN I2C device to unload hidi2c...
>>"%LOG%" echo [step] disabling device to unload driver
pnputil /disable-device "%DEVICE_ID%" >nul 2>&1
timeout /t 3 /nobreak >nul 2>&1
del /f /q "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
if exist "%TARGET_DIR%\%SYS_NAME%" goto :FAIL_LOCKED
set "DEVICE_DISABLED=1"
echo   Driver unloaded, file deleted.
>>"%LOG%" echo [OK] device disabled, file deleted

:DELETE_DONE
if exist "%DRIVERSTORE_DIR%\%SYS_NAME%" (
    del /f /q "%DRIVERSTORE_DIR%\%SYS_NAME%" >nul 2>&1
)

echo   Installing live driver copy...
>>"%LOG%" echo [step] copying live driver
copy /y "%SRC_DIR%\%NEW_SYS%" "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
if errorlevel 1 goto :FAIL_INSTALL
>>"%LOG%" echo [step] live driver copy OK

:: Re-enable the device now - the live driver is in place. A later DriverStore
:: failure must never leave the device stranded in a disabled state.
if "!DEVICE_DISABLED!"=="1" call :REENABLE

echo   Installing DriverStore copy...
>>"%LOG%" echo [step] copying DriverStore
:: DriverStore folders are SYSTEM:F / Everyone:RX - admins cannot create files
:: there until granted write on the DIRECTORY itself.
takeown /f "%DRIVERSTORE_DIR%" /a >nul 2>&1
icacls "%DRIVERSTORE_DIR%" /grant administrators:F >nul 2>&1
copy /y "%SRC_DIR%\%NEW_SYS%" "%DRIVERSTORE_DIR%\%SYS_NAME%" >nul 2>&1
if errorlevel 1 goto :FAIL_DS_ACL
icacls "%DRIVERSTORE_DIR%" /remove:g administrators >nul 2>&1
>>"%LOG%" echo [OK] driver installed

goto :CATALOG_STEP
:FAIL_DS_ACL
icacls "%DRIVERSTORE_DIR%" /remove:g administrators >nul 2>&1
goto :FAIL_DRIVERSTORE
:DRYRUN_MANUAL
echo   [dry-run] would takeown+icacls+del+copy: %TARGET_DIR%\%SYS_NAME%
echo   [dry-run] would takeown+icacls+del+copy: %DRIVERSTORE_DIR%\%SYS_NAME%
:CATALOG_STEP
:: Update catalog
if exist "%SRC_DIR%\%NEW_CAT%" (
    if "!DRYRUN!"=="1" (
        echo   [dry-run] would copy catalog: %SRC_DIR%\%NEW_CAT% to %DRIVERSTORE_DIR%\hidi2c.cat
    ) else (
        takeown /f "%DRIVERSTORE_DIR%\hidi2c.cat" /a >nul 2>&1
        icacls "%DRIVERSTORE_DIR%\hidi2c.cat" /grant administrators:F >nul 2>&1
        echo   Installing catalog...
        copy /y "%SRC_DIR%\%NEW_CAT%" "%DRIVERSTORE_DIR%\hidi2c.cat" >nul 2>&1
        if errorlevel 1 (
            echo   WARNING: Catalog copy failed. Driver may not load.
        ) else (
            echo   Catalog updated.
        )
    )
) else (
    echo   WARNING: No catalog found. Driver may not load.
)

:VERIFY
echo.
echo [6/6] === Verification ===
set "INSTALLED_VERSION="
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-Item '%TARGET_DIR%\%SYS_NAME%').VersionInfo.FileVersion" 2^>nul') do set "INSTALLED_VERSION=%%a"
echo   Current file version: !INSTALLED_VERSION!
>>"%LOG%" echo [step] file version now: !INSTALLED_VERSION!
if "!DRYRUN!"=="1" goto :VERIFY_DONE
echo %INSTALLED_VERSION%|findstr /c:".1150" >nul
if errorlevel 1 goto :VERIFY_BAD
echo   Version check passed: .1150 in place.
>>"%LOG%" echo [OK] version .1150 confirmed
goto :VERIFY_DONE
:VERIFY_BAD
echo   [WARNING] Version is not .1150 - the install may not have taken!
>>"%LOG%" echo [WARN] version mismatch after install
:VERIFY_DONE
>>"%LOG%" echo [OK] verification complete
if "!DRYRUN!"=="1" (
    echo   [dry-run] installed version would be: 10.0.26100.1150
)

echo.
echo === Done ===
if "!DRYRUN!"=="1" goto :DRYRUN_DONE
echo Reboot to normal Windows. If the trackpad doesn't work,
echo boot back to Safe Mode and run hidi2c_REVERT.bat
goto :CLEARFLAG

:: ==================== FAILURE PATHS ====================

:FAIL_ADMIN
echo [ERROR] Must run as Administrator.
>>"%LOG%" echo [ERROR] Must run as Administrator.
pause
goto :CLEARFLAG

:FAIL_SRC_SYS
echo [ERROR] %NEW_SYS% not found in %SRC_DIR%
>>"%LOG%" echo [ERROR] %NEW_SYS% not found in %SRC_DIR%
pause
goto :CLEARFLAG

:FAIL_SIG
echo [ERROR] Signature check failed. Aborting.
>>"%LOG%" echo [ERROR] Signature check failed. Aborting.
pause
goto :CLEARFLAG

:FAIL_INSTALL
echo [ERROR] Failed to install. Restoring backup...
>>"%LOG%" echo [ERROR] Failed to install. Restoring backup...
copy /y "%BACKUP_DIR%\%BACKUP_NAME%" "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
if errorlevel 1 goto :TRY_FALLBACK_RESTORE
echo   Backup restored.
>>"%LOG%" echo [OK] backup restored
goto :FAIL_INSTALL_PAUSE
:TRY_FALLBACK_RESTORE
copy /y "%FALLBACK_BAK%" "%TARGET_DIR%\%SYS_NAME%" >nul 2>&1
if errorlevel 1 goto :RESTORE_FAILED
echo   Fallback .8972 restored from Downloads.
>>"%LOG%" echo [OK] fallback .8972 restored
goto :FAIL_INSTALL_PAUSE
:RESTORE_FAILED
echo [CRITICAL] Both live backup and fallback restore failed. No driver file installed.
>>"%LOG%" echo [CRITICAL] restore failed - no driver installed
echo Manual intervention: copy any hidi2c_*.sys from Downloads to
echo C:\Windows\System32\drivers\hidi2c.sys, or restore from WinRE.
:FAIL_INSTALL_PAUSE
if "!DEVICE_DISABLED!"=="1" call :REENABLE
pause
goto :CLEARFLAG

:FAIL_LOCKED
if "!DEVICE_DISABLED!"=="1" call :REENABLE
echo [ERROR] Could not delete %SYS_NAME% - the file is locked by a running driver.
>>"%LOG%" echo [ERROR] delete failed - file still locked after device disable
echo.
echo The original driver is still in place. Nothing was changed.
echo Options:
echo   1. Reboot to Safe Mode MINIMAL (F4) and run this script again
echo   2. From WinRE: copy %SRC_DIR%\%NEW_SYS% over %TARGET_DIR%\%SYS_NAME%
echo.
pause
goto :CLEARFLAG

:FAIL_DRIVERSTORE
echo [ERROR] DriverStore copy failed. Live driver was replaced but DriverStore was not.
>>"%LOG%" echo [ERROR] DriverStore copy failed.
echo On next boot, Windows may restore the old driver from DriverStore.
echo Re-run this script or run hidi2c_REVERT.bat from Safe Mode.
pause
goto :CLEARFLAG

:DRYRUN_DONE
echo *** DRY RUN COMPLETE - no changes were made ***
echo Remove /dryrun to execute for real.
goto :CLEARFLAG
:NO_FALLBACK
echo [ERROR] No fallback backup found. Cannot proceed safely.
>>"%LOG%" echo [ERROR] No fallback backup found.
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
>>"%LOG%" echo [step] clearing safeboot flag
bcdedit /deletevalue {current} safeboot >nul 2>&1
if errorlevel 1 (
    echo   NOTE: safeboot flag not present or not cleared.
    echo   If you boot back into Safe Mode, run: bcdedit /deletevalue {current} safeboot
) else (
    echo   safeboot flag cleared.
)
echo.
pause
exit /b 0

:REENABLE
if "!DEVICE_DISABLED!"=="1" (
    echo   Re-enabling %DEVICE_ID% ...
    pnputil /enable-device "%DEVICE_ID%" >nul 2>&1
    >>"%LOG%" echo [step] device re-enabled
    set "DEVICE_DISABLED=0"
)
exit /b
