# MacBookPro16,1 graphics on Omarchy

Experimental Apple **Falcon SMC firmware support for amdgpu** on the 16-inch
2019 MacBook Pro. The internal panel stays on AMD, as it did in the macOS
configuration examined here, and memory-clock DPM stays available in `auto`.
The repository name is retained, but Intel-primary hybrid routing is no longer
the installation path.

On the reference machine, the patched driver successfully traversed
**95 → 496 → 95 → 736 → 750 → 736 → 496 → 750 MHz**, including the previously
failing intermediate state. Every step produced 12 exact clock samples, with
no SMU/ring/reset errors found in the captured kernel log. Automatic policy
and the display were restored afterward. This is one short test, not a claim
that graphics, suspend or hybrid GPU switching are finished.

## What the patch does

- Selects `amdgpu/navi14_falcon_smc.bin` with **`amdgpu.apple_falcon=1`** on the
  exact tested board. Missing selected firmware fails initialization rather
  than silently falling back to the public image.
- Requires the known image version/size and reported firmware interface.
- Reads Falcon's legacy metrics layout in both the hwmon and GPU-metrics paths.
- Sends Falcon's `0x4b(1)` UCLK rule after feature enable, through the hardware
  setup used by boot, reset and resume. Initialization errors are returned.
- Avoids generic UMC messages absent from Falcon and rejects an unsupported
  fan-boost request.

There is **no permanent clock pin, userspace governor, forced Intel routing or
PCI suspend bypass** in the active patch. The earlier workarounds and installer
have been removed. The separate Titan Ridge investigation is preserved under
[research/titan-ridge](research/titan-ridge/README.md), outside the active patch
set. It is not part of the tested Falcon configuration.

## Supported test configuration

| Component | Verified configuration |
|---|---|
| Machine | MacBookPro16,1, one reference machine |
| GPU | Navi14 `1002:7340 / 106b:020f`, revision `0x40`, MP1 11.0.5 |
| Kernel | `7.2.4-arch1-Watanare-T2-1-t2`, packaged T2 changes retained |
| Firmware | Apple Falcon `0x04350b03` (53.11.3), interface `0x36`, PSP loading |
| Panel | AMD eDP, 3072×1920 at 60 Hz |
| Memory DPM | All four levels available; `auto` restored after testing |

Repeated transitions under load, cold-boot reliability, suspend/resume,
external displays and other boards/kernel releases remain unvalidated with
this candidate. Touch ID is not addressed. Earlier sleep/power measurements
from the Intel-routing workaround do not describe this configuration.

## Use it

1. Read [migration notes](docs/MIGRATION.md) if you installed an older version.
2. Follow [build and installation instructions](docs/INSTALL.md). Only
   `amdgpu.ko` needs rebuilding against the exact installed kernel headers.
3. Extract the known signed firmware **locally** from your macOS collection
   with [tools/extract-firmware.py](tools/extract-firmware.py). No Apple firmware,
   prebuilt modules or machine-specific boot images are included here.
4. Test using a separate boot entry that embeds the candidate module and
   firmware, retaining a self-contained recovery entry.

See [kernel details](kernel/README.md) for the protocol changes and remaining
Apple policy differences, and [validation](docs/VALIDATION.md) for measured
results and their limits. The old automatic installer is intentionally gone:
its global clock/routing/service changes do not implement this setup.

## Licence

Kernel patches are GPL-2.0-only. Scripts, configuration and documentation are
MIT. These licences do not grant rights to Apple's firmware; the extraction
tool operates on files supplied locally by the user.
