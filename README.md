# hidi2c.sys Driver Rollback (Windows 11 24H2 / 26100)

Scripts to replace a regression-introducing `hidi2c.sys` (`10.0.26100.8972`) with the
last known-good build (`10.0.26100.1150`), for machines whose I2C HID trackpad stops
responding or freezes on wake.

The scripts are the artefact. **No driver binaries are distributed here** — see
[Prerequisites](#prerequisites).

## Background

`hidi2c.sys` is the Microsoft I2C HID miniport: the kernel driver between the I2C HID
bus and the HID class stack. On affected machines, `.8972` causes the precision
touchpad to drop out or freeze after resume. Rolling back to `.1150` resolves it.

The driver file cannot be replaced while it is loaded. `sc stop hidi2c` fails with
error 1052 (the driver is not stoppable), and `PendingFileRenameOperations` silently
no-ops for this file. This script solves the lock by **disabling the parent I2C HID
device**, which unloads the driver and releases the file, then re-enabling it so the
replacement loads.

## Prerequisites

Place these in `C:\Users\<you>\Downloads` (or edit `SRC_DIR` in the script):

| File | Purpose |
|---|---|
| `hidi2c_26100_1150_SIGNED.sys` | Replacement driver, `10.0.26100.1150` |
| `hidi2c_1150.inf` | Matching INF (`DriverVer = 10.0.26100.1150`) |
| `hidi2c_26100.8972.backup.sys` | Fallback copy of the original, for restore |

The `.sys` must be a genuine Microsoft-signed binary. Verify before use:

```powershell
Get-AuthenticodeSignature .\hidi2c_26100_1150_SIGNED.sys |
    Select-Object Status, IsOSBinary, @{n='Signer';e={$_.SignerCertificate.Subject}}
```

Expect `Status: Valid`, `IsOSBinary: True`, signer `CN=Microsoft Windows`.
The script checks this itself at step 1 and aborts if the signature is not valid.

## Machine-specific settings

The scripts are written for the machine they were developed on and hardcode these
values. Change them in the `set` block near the top of `hidi2c_safe_mode_swap.bat`
(and the matching `BACKUP_DIR` in `hidi2c_REVERT.bat`) to use them elsewhere.

| Variable | Default | Notes |
|---|---|---|
| `SRC_DIR` | `C:\Users\<you>\Downloads` | Where the driver files sit |
| `TARGET_DIR` | `C:\Windows\System32\drivers` | Do not change |
| `DRIVERSTORE_DIR` | `...\FileRepository\hidi2c.inf_amd64_<hash>` | **Hash is machine-specific** — check with `pnputil /enum-drivers` |
| `BACKUP_DIR` | `C:\Users\<you>\Desktop\hidi2c_backups` | Backup destination |
| `LOG` | `C:\Users\<you>\Desktop\hidi2c_swap_log.txt` | Run log |
| `DEVICE_ID` | `ACPI\ELAN0788\4&18EA2290&0` | **Your I2C HID device instance ID** — find with `Get-PnpDevice` (see below) |
| `FALLBACK_BAK` | `...\hidi2c_26100.8972.backup.sys` | Original driver, for restore |

Find your own device instance ID:

```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -eq 'I2C HID Device' } |
    Select-Object -ExpandProperty InstanceId
```

If `DRIVERSTORE_DIR` does not exist on your machine, the DriverStore steps are skipped
by the `if exist` guards and the swap still works — see the caveat below.

## Usage

Run **as Administrator**, from an elevated Command Prompt:

```cmd
cd C:\Users\<you>\Desktop
hidi2c_safe_mode_swap.bat            :: perform the swap
hidi2c_safe_mode_swap.bat /dryrun    :: show what would happen, change nothing
```

The script relaunches itself inside a persistent `cmd /k`, so the window stays open on
every path — including a crash — and output remains readable.

### It works in normal Windows

Safe Mode is **not required**. The device-disable step unloads `hidi2c` and releases
the file lock, so the swap completes in a normal session. Safe Mode MINIMAL (F4) is
still the more conservative option if you prefer it, and is the fallback the script
recommends if the delete cannot be made to succeed.

The trackpad will be unresponsive for a few seconds while the device is disabled, then
returns once the new driver loads.

### Rollback

```cmd
hidi2c_REVERT.bat            :: restore the pre-swap backup
hidi2c_REVERT.bat /dryrun
```

The backup is written to `hidi2c_backups\hidi2c.sys.before-swap.bak` and is verified by
hash at swap time.

## What the swap does

1. Verify the Authenticode signature of the replacement binary — abort if not `Valid`
2. Copy the live driver to `hidi2c_backups\hidi2c.sys.before-swap.bak` (non-fatal; a
   fallback copy in `Downloads` is used if this fails)
3. Take ownership of the live file and grant Administrators write
4. Delete the old file. **If it survives** — meaning the driver is still loaded and the
   file is still locked — disable the parent device, retry, and abort cleanly if it
   still will not go
5. Copy the replacement into `System32\drivers`, then re-enable the device
   *immediately* (never after optional later steps, so a later failure cannot strand
   the device in a disabled state)
6. Verify the installed file reports version `.1150`, warning loudly on mismatch

Every exit path pauses and clears the `safeboot` flag.

## Notes and caveats

**The DriverStore step is cosmetic on machines where the package is orphaned.**
`pnputil /enum-drivers` may list no `hidi2c` package at all, in which case
`DriverStore\FileRepository\hidi2c.inf_amd64_<hash>` is an unregistered leftover folder
rather than a package Windows will fall back to. The script's DriverStore copy is then
belt-and-braces, not a real protection.

**A registered `.1150` package cannot be staged from these files.** `pnputil
/add-driver` requires a signed catalog, and the INF here carries no `CatalogFile=`
directive. Windows component catalogs (e.g. `hidi2c_26100.1_catalog.cat`) do not cover
`hidi2c.sys` and cannot validate such a package. Do not work around this by disabling
driver signature enforcement.

**The real residual exposure is WinSxS**, not DriverStore: a component repair (`SFC`,
`DISM /RestoreHealth`) or a Windows Update driver push can reinstate `.8972`.

## Verification

```cmd
:: version actually installed
powershell -NoProfile -Command "(Get-Item C:\Windows\System32\drivers\hidi2c.sys).VersionInfo.FileVersion"

:: driver loaded
sc query hidi2c

:: device healthy
powershell -NoProfile -Command "Get-PnpDevice | Where-Object InstanceId -match 'ELAN0788' | Select Status,FriendlyName"
```

To prove the installed file is byte-identical to the intended source:

```cmd
certutil -hashfile C:\Windows\System32\drivers\hidi2c.sys SHA256
certutil -hashfile C:\Users\<you>\Downloads\hidi2c_26100_1150_SIGNED.sys SHA256
```

## Editing these scripts

Both `.bat` files **must** keep CRLF line endings. cmd.exe resolves `goto` labels by
scanning for CR-terminated lines; an LF-only file fails with

```
The system cannot find the batch label specified - BACKUP_DONE
```

even though the label is present — and the failure moves to a different label after
each edit, which makes it look like several unrelated bugs. Verify after every change:

```python
d = open(path, 'rb').read()
print('CRLF:', d.count(b'\r\n'), 'LF-only:', d.count(b'\n') - d.count(b'\r\n'))
```

See `docs/pitfalls.md` for the other batch-script traps these scripts hit.

## Replacement binary (release asset)

The replacement `hidi2c.sys` (`10.0.26100.1150`) is **not** in this repository. It is
attached to the GitHub Release for this repo as `hidi2c-1150-kit.zip`.

- SHA-256 of `hidi2c-1150.sys` inside the zip: `B9A930357CF1DB021ECA9AD416368DE913BBF62D875330164D58D733E8750235`
- Verify after download: `certutil -hashfile hidi2c-1150.sys SHA256`
- Extract the zip; place `hidi2c_26100_1150_SIGNED.sys` in your `Downloads`
  folder (or set `SRC_DIR`) before running the swap script.

The binary is Microsoft's; redistribution is under their terms.

## Licence

Scripts: MIT. Driver binaries are Microsoft's, redistributed under their own terms —
which is why none are included here.
