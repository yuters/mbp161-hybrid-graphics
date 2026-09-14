# Falcon v2 validation — 12 September 2026

Reference: MacBookPro16,1, Navi14 `1002:7340 / 106b:020f` revision `0x40`, kernel
`7.2.4-arch1-Watanare-T2-1-t2`. The tested module's srcversion was
`6AA8D5F52AD5DB85D2CFADC`. Apple firmware reported `0x04350b03`, interface `0x36`.

## Results

| Test | Observation | Scope |
|---|---|---|
| Falcon v2 boot | Correct module, successful `0x4b(1)`, AMD internal panel active | One candidate boot |
| Desktop, 180 seconds | 346 samples, all exactly 750 MHz | No intermediate-state coverage |
| DPMS off/on | 750 → 95 → 750 MHz; display restored | Lowest/highest transitions |
| Targeted panel-off test | 95 → 496 → 95 → 736 → 750 → 736 → 496 → 750 MHz | Each target held for 3 seconds with 12 exact matching samples |
| Cleanup | `auto` restored before display enabled | No persistent clock override |
| Kernel log | No matching SMU/ring/reset/error markers in the recorded check | Absence of errors in this run |

The targeted test first confirmed the panel was off and `auto` had settled to
95 MHz. It used the supported `power_dpm_force_performance_level=manual` and
`pp_dpm_mclk` interfaces, without modifying the power table. Entry to 736 MHz
worked from both 95 and 750 MHz. Intermediate states had not appeared in the
normal-use capture; this test measures requested transitions rather than
proving the normal governor chooses those states under a workload.

Machine-readable results:

- [Target samples](validation/2026-09-12-targeted-summary.json)
- [Post-test check](validation/2026-09-12-targeted-verification.json)

These are compact result records. Full local journals, root-device identifiers,
firmware binaries and boot images are not committed. The records are not an
independent reproduction on another machine.

## Build and firmware checks

Only amdgpu was rebuilt, against the installed kernel headers, with no compiler
warnings/errors. The test and stock recovery UKIs were extracted to verify
exact embedded kernel/module/command-line bytes; the Falcon firmware matched
the packaged output. Stock recovery embedded the packaged stock module rather
than depending on a global `updates/` override.

The extraction tool finds identical payloads at different collection offsets
and rejects corrupted payloads/templates. The signed payload is unchanged;
container version and payload checksum are updated, while Linux's appended
power table is preserved.

| Artifact | SHA-256 |
|---|---|
| Signed Apple payload | `db06582c2dc1a3bf625e910b9f4ebae9ff4b880737407f6bca6a4d0b8bc45281` |
| Decompressed Linux template | `ffffaa9068ff481b653dc129abb13b7723a3d3d480b81685e90d0bf84751ea7a` |
| Packaged Falcon container | `7a5053cd96e519021830dbd698875c273f63eab67998c9538c09948b8ce250e5` |

## T2 NCM after deep sleep (13 September 2026)

Separate from Falcon clocks. Stock `t2bce_vhci` `B8FCE43DDFBFB6770941DC0`,
`cdc_ncm` `964E35070A50E7AD7BD2970`. One `mem_sleep=deep` cycle. After
wake, SET_INTERFACE data alt 0 then 1 both returned 0, TX bytes kept
increasing with 0 errors, no `NETDEV WATCHDOG`, and no
`parent should not be sleeping`. See [T2-NCM-S3.md](T2-NCM-S3.md).

## Still to test

Repeated transitions with GPU/memory work; cold and warm boots; AC/battery;
graphics suspend/resume and reset; external displays; other machines;
repeated NCM S3 cycles. A successful short clock test does not establish
memory-data integrity under load, reliable graphics suspend,
macOS-equivalent policy or a completed hybrid-graphics solution.

When measuring clocks, use the exact value from `hwmon/freq2_input` in Hz.
The `pp_dpm_mclk` stars use a 25-MHz tolerance, so both 736 and 750 MHz may be
starred at once. Never count that as evidence of visiting both states.
