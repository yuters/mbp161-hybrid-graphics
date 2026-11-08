# MacBookPro16,1 graphics on Omarchy

Experimental Apple **Falcon SMC firmware support for amdgpu** on the 16-inch
2019 MacBook Pro. The internal panel stays on AMD, as it did in the macOS
configuration examined here, and memory-clock DPM stays available in `auto`.
The repository name is retained, but Intel-primary hybrid routing is no longer
the installation path.

As of November 8, 2026, the reference machine has Omarchy 4.5 and
**patched T2 7.2.11 installed**, using Falcon, NCM sleep and Apple AV adapter
fixes in its normal Omarchy boot entry. Build and boot-image verification
passed. The first 7.2.11 boot loaded the expected drivers and Falcon firmware;
the user confirmed display, keyboard, trackpad and speaker audio. Two deep-sleep
cycles completed, including an approximately 6-hour-20-minute interval, with
normal unlock, input and speaker audio confirmed after the latest wake.
The previous patched 7.2.9 setup passed one deep-sleep/unlock cycle on
Omarchy 4.5. See [current kernel status](docs/KERNEL-7.2.11.md).

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

## Original Falcon clock-transition test

| Component | Verified configuration |
|---|---|
| Machine | MacBookPro16,1, one reference machine |
| GPU | Navi14 `1002:7340 / 106b:020f`, revision `0x40`, MP1 11.0.5 |
| Kernel | `7.2.4-arch1-Watanare-T2-1-t2`, packaged T2 changes retained |
| Firmware | Apple Falcon `0x04350b03` (53.11.3), interface `0x36`, PSP loading |
| Panel | AMD eDP, 3072×1920 at 60 Hz |
| Memory DPM | All four levels available; `auto` restored after testing |

Repeated transitions under load, cold-boot reliability and other boards remain
unvalidated with the Falcon candidate. Later sleep and external-display
results on 7.2.6 are scoped below; they do not establish general reliability.
Touch ID is not addressed. Earlier
sleep/power measurements from the Intel-routing workaround do not describe
this configuration.

T2 internal USB Ethernet (`cdc_ncm` on `05ac:8233`) hung after deep sleep
on the reference machine even when Falcon graphics resumed. Linux left
the data alternate at 1 across sleep; native AppleUSBNCMData sets alt 0
before sleep. That is [patch 0002](docs/T2-NCM-S3.md), independent of
Falcon.

Historical hibernation (S4) tests used [patch 0003](docs/HIBERNATION.md) for
the T2 BCE drivers and a Limine loader patch. Hibernation is disabled on the
current setup; the rebased patch has an unresolved DMA teardown failure path
and is excluded. The image-loading kernel's T2
sign-on destroys every firmware queue of the hibernated kernel, so the
patch rebuilds the T2 transport on restore instead of restoring saved
state; the loader patch keeps the firmware memory map identical across
boots. The initial revision passed 5/5 real restores on
`7.2.6-arch2-Watanare-T2-2-t2`, where Falcon and NCM also run unchanged.
The later teardown/audio revision passed one real restore; the subsequent
audio probe-unwind fix is build-checked only. See the validation table before
attributing older results to the current patch.

A 4K display on Apple's USB-C Digital AV Multiport Adapter was black at
4K@60: the adapter advertises DSC and 4:2:2 but neither works through it,
and macOS uses neither. [Patch 0004](docs/EXTERNAL-DISPLAY.md) makes amdgpu
ignore both for that adapter, so 4K@60 falls back to YCbCr 4:2:0 as on macOS.

## Use it

1. Read [migration notes](docs/MIGRATION.md) if you installed an older version.
2. Follow [build and installation instructions](docs/INSTALL.md) for Falcon
   and the optional adapter fix in `amdgpu.ko`. The active NCM fix additionally
   requires rebuilding `cdc_ncm.ko`; see [T2 NCM S3](docs/T2-NCM-S3.md).
3. Extract the known signed firmware **locally** from your macOS collection
   with [tools/extract-firmware.py](tools/extract-firmware.py). No Apple firmware,
   prebuilt modules or machine-specific boot images are included here.
4. Test using a separate boot entry that embeds the candidate module and
   firmware, retaining a self-contained recovery entry.

See [kernel details](kernel/README.md) for the protocol changes and remaining
Apple policy differences, [validation](docs/VALIDATION.md) for Falcon
measurements, and [T2 NCM S3](docs/T2-NCM-S3.md) for internal Ethernet after
sleep, [hibernation](docs/HIBERNATION.md) for S4, and
[external display](docs/EXTERNAL-DISPLAY.md) for the USB-C AV adapter. The old automatic installer is intentionally gone: its global
clock/routing/service changes do not implement this setup.

See the [2026-10-04 assessment](docs/PATCH-REVIEW-2026-10-04.md) for the
KAIT2EN changes reviewed that week, the 7.2.8 target and the BCE rebase. The
[2026-09-27 review](docs/PATCH-REVIEW-2026-09-27.md) records the earlier findings.
The subsequent [7.2.8 hybrid build](docs/HYBRID.md) includes the refreshed
KAIT2EN patches and documents the first test image's scope and remaining S4 work.
The [stock 7.2.9 test](docs/STOCK-7.2.9.md) records why basic boot success
did not justify removing the patches: the subsequent sleep/login test failed.

## Licence

Kernel patches are GPL-2.0-only. Scripts, configuration and documentation are
MIT. These licences do not grant rights to Apple's firmware; the extraction
tool operates on files supplied locally by the user.
