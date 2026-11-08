# elan0788-trackpad-fix

ELAN precision touchpad (`ACPI\ELAN0788`, HID-over-I2C) on the HP Victus 15-fa1xxx
intermittently stutters and dies. This repo holds the
diagnostics, the evidence, and a partial mitigation: rolling `hidi2c.sys` back
from `.8972` to `.1150`.

No driver binaries are committed here. The replacement binary is distributed as a
release asset (see [Binary](#binary)).

## What we found

- The shipped driver is `hidi2c.sys` **10.0.26100.8972** caused huge problems. An older build,
  **10.0.26100.1150**, makes failures less frequent and severe. `.1150` is the first signed older
  driver I found that reduced the problems.
- The issue is hard to diagnose.  The PnP device stays `OK`, all services
  stay Running, and no arrive/remove (400/410) events fire during a failure.
  The fault is invisible to Device Manager.
- A full power drain (EC reset) revives the pad; a warm reboot does not.
  Fast Startup (`HiberbootEnabled=1`) means "Shut down" is a hybrid sleep, not
  a cold boot.
- Power management (device + I2C controller) and the D-state (D1) were ruled
  out as discriminators.

Full evidence: [`docs/bug-report.md`](docs/bug-report.md).

## Contents

| Path | Purpose |
|---|---|
| `docs/pitfalls.md` | Batch-script traps hit while building the above |
| `docs/bug-report.md` | Evidence-only report for Microsoft Feedback Hub / ELAN |
| (release asset) `hidi2c-1150-kit.zip` | `.1150` binary + `apply-1150.ps1` + `verify-hidi2c.ps1` + both `.bat` scripts |

## Download

`hidi2c-1150-kit.zip`.

- SHA-256 of `hidi2c-1150.sys` inside the zip:
  `B9A930357CF1DB021ECA9AD416368DE913BBF62D875330164D58D733E8750235`
- Verify after download: `certutil -hashfile hidi2c-1150.sys SHA256`
- Extract the zip to a folder. It contains `hidi2c-1150.sys`, `apply-1150.ps1`,
  `verify-hidi2c.ps1`, `hidi2c_safe_mode_swap.bat`, and `hidi2c_REVERT.bat`.
  Place `hidi2c-1150.sys` in your `Downloads` folder (or set `SRC_DIR`) before
  running the swap script; `apply-1150.ps1` expects the binary in the same
  folder as itself.
- `apply-1150.ps1` (inside the zip) is a self-elevating re-apply (hash-checks
  the saved copy, backs up the current binary, swaps, verifies). Run
  `verify-hidi2c.ps1` (also in the zip) afterwards, or periodically, to detect
  servicing reverts.

The binary is Microsoft's; redistribution is under their terms.

## Prerequisites (batch scripts)

Place these in `C:\Users\<you>\Downloads` (or edit `SRC_DIR` in the script):

| File | Purpose |
|---|---|
| `hidi2c_26100_1150_SIGNED.sys` | Replacement driver, `10.0.26100.1150` (from the release kit, renamed) |
| `hidi2c_26100.8972.backup.sys` | Fallback copy of the original, for restore |

The `.sys` must be a genuine Microsoft-signed binary. Verify before use:

```powershell
Get-AuthenticodeSignature .\hidi2c_26100_1150_SIGNED.sys |
    Select-Object Status, IsOSBinary, @{n='Signer';e={$_.SignerCertificate.Subject}}
```

Expect `Status: Valid`, `IsOSBinary: True`, signer `CN=Microsoft Windows`.

## Machine-specific settings

The scripts are written for the machine they were developed on and hardcode these
values. Change them in the `set` block near the top of `hidi2c_safe_mode_swap.bat`
(and the matching `BACKUP_DIR` in `hidi2c_REVERT.bat`) to use them elsewhere.

| Variable | Default | Notes |
|---|---|---|
| `SRC_DIR` | `%USERPROFILE%\Downloads` | Where the driver files sit |
| `TARGET_DIR` | `C:\Windows\System32\drivers` | Do not change |
| `DRIVERSTORE_DIR` | `...\FileRepository\hidi2c.inf_amd64_<hash>` | **Hash is machine-specific** — check with `pnputil /enum-drivers` |
| `BACKUP_DIR` | `%USERPROFILE%\Desktop\hidi2c_backups` | Backup destination |
| `LOG` | `%USERPROFILE%\Desktop\hidi2c_swap_log.txt` | Run log |
| `DEVICE_ID` | `ACPI\ELAN0788\4&18EA2290&0` | **Your I2C HID device instance ID** — find with `Get-PnpDevice` (see below) |
| `FALLBACK_BAK` | `...\hidi2c_26100.8972.backup.sys` | Original driver, for restore |

Find your own device instance ID:

```powershell
Get-PnpDevice | Where-Object { $_.FriendlyName -eq 'I2C HID Device' } |
    Select-Object -ExpandProperty InstanceId
```

If `DRIVERSTORE_DIR` does not exist on your machine, the DriverStore steps are
skipped by the `if exist` guards and the swap still works.

## Usage

Run **as Administrator**, from an elevated Command Prompt:

```cmd
cd C:\Users\<you>\Desktop
hidi2c_safe_mode_swap.bat            :: perform the swap
hidi2c_safe_mode_swap.bat /dryrun    :: show what would happen, change nothing
```

The script relaunches itself inside a persistent `cmd /k`, so the window stays
open on every path — including a crash — and output remains readable.

### It works in normal Windows

Safe Mode is **not required**. The device-disable step unloads `hidi2c` and
releases the file lock, so the swap completes in a normal session. Safe Mode
MINIMAL (F4) is still the more conservative option if you prefer it.

The trackpad will be unresponsive for a few seconds while the device is
disabled, then returns once the new driver loads.

### Rollback

```cmd
hidi2c_REVERT.bat            :: restore the pre-swap backup
hidi2c_REVERT.bat /dryrun
```

## What the swap does

1. Verify the Authenticode signature of the replacement binary — abort if not `Valid`
2. Copy the live driver to `hidi2c_backups\hidi2c.sys.before-swap.bak`
3. Take ownership of the live file and grant Administrators write
4. Delete the old file. **If it survives** — meaning the driver is still loaded and the
   file is still locked — disable the parent device, retry, and abort cleanly if it
   still will not go
5. Copy the replacement into `System32\drivers`, then re-enable the device
   *immediately* (never after optional later steps, so a later failure cannot strand
   the device in a disabled state)
6. Verify the installed file reports version `.1150`, warning loudly on mismatch

Every exit path pauses and clears the `safeboot` flag.

## Caveats

- **The DriverStore step is cosmetic on machines where the package is orphaned.**
  `pnputil /enum-drivers` may list no `hidi2c` package at all.
- **A registered `.1150` package cannot be staged from these files.** `pnputil
  /add-driver` requires a signed catalog, and the INF here carries no
  `CatalogFile=` directive.
- **The real residual exposure is WinSxS**, not DriverStore: a component repair
  (`SFC`, `DISM /RestoreHealth`) or a Windows Update driver push can reinstate
  `.8972`. Re-run `verify-hidi2c.ps1` after updates.

## Verification

```cmd
powershell -NoProfile -Command "(Get-Item C:\Windows\System32\drivers\hidi2c.sys).VersionInfo.FileVersion"
sc query hidi2c
certutil -hashfile C:\Windows\System32\drivers\hidi2c.sys SHA256
certutil -hashfile C:\Users\<you>\Downloads\hidi2c_26100_1150_SIGNED.sys SHA256
```

The two hashes must match.

## Editing these scripts

Both `.bat` files **must** keep CRLF line endings. cmd.exe resolves `goto` labels by
scanning for CR-terminated lines; an LF-only file fails with

```
The system cannot find the batch label specified - BACKUP_DONE
```

even though the label is present. See `docs/pitfalls.md` for the other batch-script
traps these scripts hit.

## Licence

Scripts: MIT. Driver binaries are Microsoft's, redistributed under their own
terms — which is why none are included here.
