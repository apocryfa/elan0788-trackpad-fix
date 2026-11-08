# Batch-script pitfalls hit while building this

Each of these produced a failure that looked like a logic bug but was not. They cost
several Safe Mode reboots to find. Listed in the order they bit.

## 1. LF line endings break `goto`

**Symptom**

```
The system cannot find the batch label specified - BACKUP_DONE
```

while `:BACKUP_DONE` is plainly in the file.

**Cause** — cmd.exe resolves labels by scanning for CR-terminated lines. Edit tools
that write LF-only produce a file with no CR bytes at all, and label lookup fails.

**Why it was hard to find** — the failure is *migratory*. Each edit shifted which label
was reached first, so it presented as a series of unrelated bugs, and twice as a script
that exited silently mid-way with no error at all.

**Rule** — after any `.bat` edit, re-check and convert:

```python
d = open(path, 'rb').read()
d = d.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
open(path, 'wb').write(d)
```

A `.gitattributes` with `*.bat text eol=crlf` prevents this recurring via git.

## 2. A successful command destroys `errorlevel`

```bat
bcdedit /deletevalue {current} safeboot >nul 2>&1
>>"%LOG%" echo [OK] safeboot cleared   REM resets errorlevel to 0
if errorlevel 1 ( ... )                REM never true
```

The logging line sits between the command and its check, so the check is dead and the
failure message never appears. Log the step **before** the command, never between a
command and its `if errorlevel`.

## 3. `>` inside `echo` text is a redirect

`echo ... -> ...` and `echo ... > Troubleshoot > Advanced` are parsed as redirections.
This produced `Access is denied.` and created stray directories on the Desktop named
`Troubleshoot`, `Advanced`, `F5`. Write `to` or `-` instead of `>` in prose.

## 4. `&` inside an echoed variable splits the command

`echo Disabling %DEVICE_ID% ...` where the value is `ACPI\ELAN0788\4&18EA2290&0`
executes three commands:

```
'18EA2290' is not recognized as an internal or external command
```

Quoting does not protect a variable inside `echo` text. Keep raw IDs out of
human-readable output; quoted use in real commands (`pnputil /disable-device "%DEVICE_ID%"`)
is fine.

## 5. `goto` inside a parenthesised block fails

Move labels outside `( ... )` blocks.

## 6. Never build filenames from `%date%`

`%date:~10,4%%date:~4,2%%date:~7,2%` yields `0/02` on DD/MM/YYYY locales, and `/` is
illegal in a filename. The backup silently failed to create. Use a fixed name.

## 7. Never strand a device in a disabled state

If a script disables a device to unlock a driver file, re-enable it **immediately**
after the step that needed the lock — never after later optional steps. A DriverStore
copy failure in a later step left the trackpad disabled and the device dead until it
was re-enabled by hand.

## 8. DriverStore FileRepository folders reject admin writes

`...\DriverStore\FileRepository\<inf>_amd64_<hash>` is `SYSTEM:(F)` + `Everyone:(RX)`.
Administrators get read-only via Everyone, so `copy` into it fails. Grant write on the
directory, copy, then remove the ACE to restore the original protection:

```bat
takeown /f "%DRIVERSTORE_DIR%" /a >nul 2>&1
icacls "%DRIVERSTORE_DIR%" /grant administrators:F >nul 2>&1
copy /y "%SRC%" "%DRIVERSTORE_DIR%\driver.sys" >nul 2>&1
icacls "%DRIVERSTORE_DIR%" /remove:g administrators >nul 2>&1
```

## 9. A `pause` only helps paths that reach it

A crash or an early `exit` closes a double-clicked window before anything is readable.
Relay in a persistent shell so the window survives any termination:

```bat
@echo off
if not "%~1"=="/wrapped" (
    cmd /k ""%~f0" /wrapped %*"
    exit /b
)
```

**Consequence** — `%~1` is now `/wrapped`, so flag detection must scan all args:

```bat
set "DRYRUN=0"
for %%a in (%*) do if /i "%%a"=="/dryrun" set "DRYRUN=1"
```

## 10. Verify by running, not by reading

A dry-run flag that touches nothing is the cheapest real test. Grep the output for the
specific error string rather than reasoning about the code:

```bash
timeout 15 cmd.exe /c "script.bat /dryrun" 2>&1 | grep -i "cannot find\|denied"
```

The wrapper holds the window open, so `timeout` expiring is normal — check the output,
not the exit code.

## Verifying a kernel driver swap actually took

Do not trust the script's own success message. Check all four:

```cmd
powershell -NoProfile -Command "(Get-Item C:\Windows\System32\drivers\hidi2c.sys).VersionInfo.FileVersion"
sc query hidi2c
certutil -hashfile C:\Windows\System32\drivers\hidi2c.sys SHA256
certutil -hashfile <source>.sys SHA256
```

The two hashes must match. A driver file can be replaced on disk while the running
image stays the old one until reboot — the version string and hash confirm the file,
`sc query` confirms the service, and device status confirms it loaded.
