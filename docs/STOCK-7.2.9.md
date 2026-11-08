# Stock T2 7.2.9 baseline and failed sleep test — October 14, 2026

**Stock did not pass the subsequent sleep/login test.** The user reported
failure and inability to log back in, including repeated triggering of the
previously observed race. They requested restoration of our patches on 7.2.9.
The successful awake checks below do not establish stock as a reliable daily
configuration.

The reference MacBookPro16,1 successfully booted packaged
`7.2.9-arch1-Watanare-T2-3-t2` without this repository's custom patches.
Boot ID: `44648d1f-e9b3-477c-8983-09694f6c87fa`.

The loaded amdgpu, i915, apple_gmux, four loaded BCE modules and cdc_ncm
srcversions match the installed modules. `t2gmux` is absent. The command line
has no Falcon opt-in or experimental hybrid arguments. AMD reports public
SMU firmware `0x00352600` (53.38.0), not Apple Falcon.

## Observations

| Check | Result |
| --- | --- |
| Internal display | AMD eDP, 3072×1920 at 60 Hz |
| Keyboard, trackpad, speakers | User confirmed all work normally |
| AMD rendering | EGL offscreen test: 120 clears, correct pixel readback |
| Intel rendering | Same EGL test passed on UHD 630 |
| Failed system units | None at baseline capture |
| Fatal graphics errors | No GPU reset, ring timeout, SMU failure, oops or call trace in inspected log |
| AMD runtime power-off | Driver reports runtime PM unavailable; power/control is `on`, GPU stays active |
| AMD memory clock | Six samples at 750 MHz with performance policy `auto` |
| GPU telemetry | Reported 17–18 W and 72–73 °C over the short sample after rendering tests |
| External display | Not available; untested |
| Suspend/resume | Failed in the user's subsequent test; recovery required rebooting |
| Hibernation | Untested |

Two SDMA fence fallback messages occurred during initialization. Intel logged
missing VBT/link information and no usable display, while AMD drove the panel.
These warnings did not prevent the observed desktop or rendering tests.

This establishes that our patches are unnecessary for basic boot and the
tested input/audio/rendering functions on this machine. It does not establish
that stock firmware handles the previously problematic memory-clock
transitions: this run sampled only 750 MHz. The short telemetry sample is not
a battery-life measurement or a sustained-load test.

Captures are stored locally under
`mbp161-assessment/stock-7.2.9/44648d1f-e9b3-477c-8983-09694f6c87fa/`,
including module identities, renderer output, monitor/audio state and kernel
logs. No power policy, clocks, firmware preference or boot settings were
changed during these checks.

The failed boot's journal ends at approximately 250 seconds uptime, after
`Starting System Suspend` and freezing the session scope. No successful
resume is recorded. Several subsequent boots precede the current recovered
session (`08bcffc8-1ac8-4960-b8c7-a86cafd04a87`). This establishes failure,
but the preserved log does not identify the exact kernel race or prove which
individual patch fixes it.
