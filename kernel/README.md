# Active kernel patches

Two independent patches, both against Linux 7.2.4 with the packaged
Watanare T2 changes. No whole-kernel rebuild is required.

| Patch | Module | What it is for |
|---|---|---|
| `patches/0001-amdgpu-apple-falcon.patch` | `amdgpu` | Falcon SMC / internal AMD panel |
| `patches/0002-cdc-ncm-apple-t2-s3.patch` | `cdc_ncm` | T2 internal USB Ethernet after deep sleep |

The original three T2 AMD changes remain; 0001 does not carry or replace
them. 0002 does not change VHCI. Apply 0002 even if you are not using
Falcon; it is gated to Apple T2 NCM (`05ac:8233`). See
[T2 NCM S3](../docs/T2-NCM-S3.md).

The patch is the tested Falcon v2 implementation, with only its test-status
comment updated for publication. A new module build may have different
metadata; the reference module's srcversion is recorded in
[validation](../docs/VALIDATION.md), not prescribed for every build.

## Selection and compatibility

`amdgpu.apple_falcon` is a read-only boolean parameter, off by default.
Selection requires AMD `1002:7340`, Apple subsystem `106b:020f`, revision `0x40`,
MP1 11.0.5, a non-VF device and PSP firmware loading. Other boards retain stock
firmware selection even if the option is present.

The selected container must report version `0x04350b03` and payload size
`0x40200`; firmware must report version `0x04350b03` and interface `0x36`.
The extraction tool additionally checks the **entire signed payload hash**.
The kernel patch's version/size checks are not a payload hash check. Do not
rename an arbitrary image to the expected filename.

Both metrics readers explicitly use the legacy layout. A program-4 version
cannot safely be compared numerically against public program-0 layout-change
thresholds. Unsupported generic UMC messages `0x4e–0x50` are not used on Falcon;
a requested fan-boost setting (`0x4c`) returns `EOPNOTSUPP`. The generic Navi14
mapping does not expose `0x4d`.

## UCLK rule and remaining policy work

The decoded `0x4b(1)` handler sets a flag that changes UMC programming for
level 2. The driver sends it after feature enable, following the observed
Apple ordering. The chosen hook runs in the hardware setup for boot, reset
and resume, before the default DPM tables are published. A failed command
fails initialization instead of merely logging and continuing.

The precise hardware field semantics are not fully identified. The targeted
transition test supports this configuration on the tested board; it is not an
A/B isolation of the flag from every other difference in Apple's firmware.
The interval between feature enable and the command also needs repeated-boot
validation. Source coverage of the resume path does not prove successful
suspend/resume on hardware.

Apple additionally uploads a Boa/activity table and uses a 740-MHz ceiling.
This candidate keeps Linux's table policy and all four UCLK states, including
750 MHz. Do not add Apple's ceiling at one call site: earlier experiments
produced conflicting display hard-min and clock-max requirements. Any future
ceiling must be represented consistently in the display and power-management
paths. The validated container preserves Linux's appended power table; the
reference boot reports use of the VBIOS-provided table.

## Removed stack

The earlier gmux-to-Intel, AMD fbdev/eDP suppression and AMD PCI s2idle bypass
patches are not applied. Their historical code remains in Git history at
[`e77b03f`](https://github.com/yuters/mbp161-hybrid-graphics/tree/e77b03f).
Titan Ridge research is kept separately and is **not** an additional patch to
apply during Falcon validation.
