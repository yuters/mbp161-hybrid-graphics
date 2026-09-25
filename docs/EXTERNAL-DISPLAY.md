# External display through Apple's USB-C AV adapter

With [patch 0004](../kernel/patches/0004-drm-amd-display-apple-usb-c-av-adapter.patch),
a 4K display on Apple's USB-C Digital AV Multiport Adapter runs at 4K@60 on
the Falcon (AMD-primary) setup. Without it, 4K@60 is a black screen with the
display still reporting a signal; lower modes already worked.

The USB-C ports are wired to the AMD GPU. Tested with a Dell S2722QC on the
adapter's HDMI output, left-bottom port. The direct USB-C cable to that
display was not used (unreliable on the reference machine).

## What happens without the patch

Hotplug, EDID, link training and modesetting all succeed, with no kernel
errors. The adapter (`05ac:1463`, DP branch OUI `00-10-fa`, device id
`cHDMIb`) gives DisplayPort only two lanes: USB-C shares the other two with its
USB 3 hub. It advertises a DSC 1.2 decoder, YCbCr 4:2:2/4:2:0 pass-through and
a 600 MHz HDMI TMDS limit.

| 4K@60 as sent by amdgpu | Link | Picture |
|---|---|---|
| RGB 8 bpc + DSC 16 bpp (driver default) | 2 × HBR3 | no; adapter DSC status `0x20F = 03` (RC buffer under-run + overflow) |
| RGB + DSC at 12, 10, 8 bpp | 2 × HBR2 | no |
| YCbCr 4:2:2, no DSC | 2 × HBR3 | no |
| YCbCr 4:2:0, no DSC | 2 × HBR2 | yes |

4K@30, 2560×1440@60 and 1080p@60 fit two lanes uncompressed as RGB and always
worked.

## What macOS does

Apple's `AGDCDiagnose` on macOS 26.6.2, same machine, adapter, port and
display at 4K@60: 2 × HBR3, FEC on, **DSC disabled** (`0x160 = 0`) although the
adapter advertises it, and the adapter's own status registers show input and
output **YCbCr 4:2:0, 10-bit**, VIC 97. Its HDMI side runs above 340 MHz with
scrambling there, so the high-rate output works; the DSC path is what Apple
avoids.

## The fix

For this branch only, amdgpu forgets the DSC capability and the 4:2:2
pass-through and conversion flags when it reads the link caps. Its existing
mode validation then does the rest: RGB fails on bandwidth (DP-HDMI
converters stop at 8 bpc, so no 6 bpc RGB), 4:2:2 fails the converter check,
and 4:2:0 is chosen. That is the format macOS uses; modes that fit without
compression stay RGB. No encoding is forced anywhere.

| After the patch | Link | Encoding | Picture |
|---|---|---|---|
| 4K@60 | 2 × HBR2, no DSC | YCbCr 4:2:0, 8 bpc | yes |
| 4K@30 | 2 × HBR2, no DSC | RGB | yes |

Build: 0004 changes `amdgpu` only; build it together with the Falcon patch as
in [install](INSTALL.md). Tested module `7135E5DE` on
`7.2.6-arch2-Watanare-T2-2-t2`.

## Not covered

- macOS uses 10-bit 4:2:0; here the compositor requests 8 bpc.
- Other Apple adapters (other device ids or firmware) and other displays.
- Hibernation with this module has not been re-run separately; the change
  only affects link-capability parsing for this adapter.

## Testing pitfall

amdgpu's debugfs `force_yuv420_output` / `force_yuv422_output` also set a
`force_yuv_pixel_format` field that writing `0` does not clear, so the forced
format persists until the driver reloads. Reboot between such experiments.
