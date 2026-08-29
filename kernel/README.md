# Kernel patches

Four patches, applied in order on top of **Linux 7.2 with the
[t2linux](https://wiki.t2linux.org/) v7.2-rc6 patch stack**.

| | |
|---|---|
| `0001` | `platform/x86: apple-gmux` — switch the panel mux to the iGPU before either DRM driver binds, dropping the firmware framebuffer first. Exports `apple_gmux_panel_is_igd()`. |
| `0002` | `drm/amdgpu` — skip in-kernel fbdev when the panel is muxed to the iGPU. |
| `0003` | `drm/amd/display` — skip detect, HPD, polling and EDID on the internal eDP while it is muxed away (the "ghost eDP"). |
| `0004` | `PCI/PM` — leave six MacBookPro16,1 PCI functions untouched across s2idle. |

All four are gated on `apple_gmux_panel_is_igd()` or on an explicit DMI match
plus exact PCI IDs, so they are inert on other hardware.

## Verification status

**Verified:** all four apply cleanly with `patch -p1` to a pristine t2linux
v7.2-rc6 tree, and every file they touch compiles from that tree —
`apple-gmux.o`, `pci-driver.o`, `amdgpu_drv.o`, and the whole
`drivers/gpu/drm/amd/display/amdgpu_dm/` directory.

**Note on 0002.** The version of this change that ran on the reference machine
also tested `adev->pm.rpm_mode == AMDGPU_RUNPM_GMUX`. That enum comes from a
larger research tree, not upstream, so the condition was removed here — it was
redundant anyway, since `apple_gmux_panel_is_igd()` is already false unless
apple-gmux is bound with the mux on the iGPU. The shipped patch is therefore
*not* byte-identical to what was runtime-tested, though it is behaviourally
equivalent on this hardware.

**Not verified:** a full kernel build and boot from exactly these four patches
and nothing else. The reference machine ran them inside a larger tree that also
carried D3cold and Config3 experiments, deliberately excluded here as dead ends.

## Not included, on purpose

The research tree these came from also contains gmux Config3 / D3cold power
sequencing, debugfs research hooks, tracing, and a gmux runtime-PM gate. None of
it made the machine better and some of it can hang it. It is not here.
