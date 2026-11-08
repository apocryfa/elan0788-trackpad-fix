# Bug report draft — ELAN precision touchpad dies / misbehaves on HP Victus (Windows 11 26200)

Fill in the placeholders marked [ ]. Keep it factual; do not speculate about causes.
Two destinations: Microsoft Feedback Hub (Windows > Input / Touchpad) and ELAN support.

---

## Summary

Precision touchpad (ELAN0788, HID-over-I2C) intermittently stops responding or emits phantom
pointer movement/clicks. No error is recorded anywhere Windows exposes: the PnP device stays
`OK`, all services stay Running, the device never leaves the bus, and no event is logged.

## Environment

- Laptop: HP Victus 15-fa1xxx, SKU 878R3EA#ABU, BIOS AMI F.18 (HP ships no newer BIOS for this SKU)
- OS: Windows 11 build **26200.x** (25H2)
- Touchpad: `ACPI\ELAN0788\4&18EA2290&0`, HID-over-I2C on
  `Intel(R) Serial IO I2C Host Controller - 51E8` (`pci\ven_8086&dev_51e8`), driver 30.100.2531.31
- ELAN filter drivers: 22.2.49.3
- `hidi2c.sys`: Microsoft inbox, **10.0.26100.8972** as shipped; **10.0.26100.1150** when the
  problem is much reduced (see Workaround)

## Symptoms

1. **Dead**: pad produces no input at all. All ELAN + I2C nodes report `OK`, problem code 0.
   Persists until a power event or a device toggle (details below).
2. **Phantom**: cursor moves and clicks by itself with nobody touching the pad.
3. **Intermittent**: input drops in and out within seconds.
4. Once, Device Manager showed the ELAN node in an error state with
   `STATUS_DEVICE_POWER_FAILURE` (0xC000009E); it did not clear with a device restart.

Trigger correlation (not deterministic): resume from sleep, sometimes hibernate. Frequency
increased after the hidi2c version changed to .8972; an older binary (.1150) made failures less
severe but did not eliminate them.

## Evidence gathered

- PnP: nodes `OK`, 5 services Running, **zero** arrive/remove (400/410) events during failures.
- `DEVPKEY_Device_PowerData`: reads **D1 in both working and failing states** — not a discriminator.
- ETW: `Microsoft-Windows-SPB-HIDI2C` and `Intel-iaLPSS2-I2C` emit **no events** at default levels
  on this build, so they cannot be used to debug this.
- Kernel trace (WPR `CPU`+`Power`, analysed with `xperf -a dpcisr`): DPC/ISR counts for
  `hidi2c.sys` + `iaLPSS2_I2C_ADL.sys` over ~45–50 s windows measured
  **18 / 161 / 1118 / 7901** events across different states — i.e. the HID-over-I2C path sometimes
  performs far more interrupt work than normal use, without corresponding user-visible input.
- Fn+F11 (the EC's touchpad toggle) never reaches Windows as a keystroke, and toggling does not
  change any Windows-visible device state, so software cannot detect whether the pad is switched off.

## Requested

1. Whether `hidi2c.sys` .8972 has known regressions versus .1150 on I2C-HID precision touchpads,
   particularly around device power transitions (D3/D0) and resume from sleep.
2. Whether the ACPI/EC power sequencing for ELAN0788 on this platform is expected to gate the device
   without the OS seeing a state change — and if so, how a driver is supposed to detect it.
3. Guidance on capturing a supported trace for I2C-HID failures on 26200, given both relevant ETW
   providers are silent.

## Workaround in use

Replace the inbox `C:\Windows\System32\drivers\hidi2c.sys` with the **10.0.26100.1150** binary
(SHA-256 `B9A930357CF1DB02...`), leaving the .8972 driver package registered. Failure frequency and
severity drop notably, but this is a file swap: driver servicing may restore .8972, so it has to be
re-applied and verified after updates.

---

## Notes for the reporter (do not paste into the report)

- Do not claim a root cause; the report deliberately stops at evidence.
- Attach, if allowed: the `xperf -a dpcisr` output for the four states, and `verify-hidi2c.ps1` output.
- Feedback Hub: "Input and touch > Touchpad"; include the build number and that the ELAN node stays OK.
