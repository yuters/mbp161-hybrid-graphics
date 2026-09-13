# Migrating from the Intel-routing workaround

The former installer set up a different topology and power policy. Falcon
support does not update or undo that installation automatically. Keep its
working boot entry while preparing the new candidate; do not disable your
only working configuration before the candidate and recovery images exist.
The earlier source is preserved at
[`e77b03f`](https://github.com/yuters/mbp161-hybrid-graphics/tree/e77b03f).

## What has been removed from the active repository

| Previous component | Why it is not used with Falcon |
|---|---|
| gmux defaults to Intel (`0001`) | Candidate retains AMD panel routing |
| AMD fbdev/eDP suppression (`0002`, `0003`) | Candidate needs AMD to drive its internal eDP |
| AMD PCI s2idle bypass (`0004`) | Bypasses driver suspend; cannot validate normal Falcon resume |
| `mbp161-amdgpu-hybrid-prep` | Forces `low` and suppresses AMD eDP |
| `mbp161-amdgpu-dpm-governor` | Replaces automatic policy with a userspace low/high loop |
| uwsm env snippet | Selects Intel first and may exclude AMD when DPM is `auto` |
| Limine default-entry hook | Forces the old custom kernel to be the default |
| Old `install.sh` | Reinstalls the above instead of the tested Falcon setup |

Removing the suspend bypass does **not** mean normal suspend is fixed. It
remains unvalidated with Falcon. The Titan Ridge power-sequence patch is kept
under `research/`, because it addresses a separate problem; do not apply it
as part of the tested Falcon patch set.

## Existing installations

When ready to transition, inspect and disable the old prep/governor units
before booting the Falcon candidate. Neither should write clock policy or
connector state during a Falcon test. Keep backups of their installed files
if the old entry remains a fallback that depends on them; a separately staged
stock/Intel recovery image avoids relying on that userspace policy.

```sh
sudo systemctl disable --now mbp161-hybrid-prep.service mbp161-amdgpu-dpm-governor.service
```

This command stops policy services; it does not itself switch the current GPU
back to `auto`. Do not write `auto` on a still-running old firmware setup just
because the new documentation uses it.

Inspect these artifacts installed by the old script and back up/remove the
old repo-owned content as appropriate:

- `/etc/systemd/system/mbp161-hybrid-prep.service`
- `/etc/systemd/system/mbp161-amdgpu-dpm-governor.service`
- `/usr/local/bin/mbp161-amdgpu-hybrid-prep`
- `/usr/local/bin/mbp161-amdgpu-dpm-governor`
- `/etc/boot/hooks/post.d/80-mbp161-default-entry`
- `/etc/limine-entry-tool.d/mbp161-hybrid.conf` or `zz-mbp161-hybrid.conf`

Run `systemctl daemon-reload` after removing units. Remove the old repository
block from `~/.config/uwsm/env`, preserving unrelated user settings. Audit any
remaining `AQ_DRM_DEVICES`, `AQ_ALLOW_DGPU` and `HYPR_LID_ONLY` overrides rather
than blindly overwriting the file.

The old boot drop-in supplied `apple_gmux.force_igd=1 amdgpu.runpm=0` and a
custom kernel order. Keep those only in an intentional old/recovery entry,
not globally in the candidate. Also remove old AMD blacklists, experimental
clock-pin parameters and `amdgpu.smu_alt_smc=falcon` from the candidate command
line. Never replace storage/encryption/root arguments with someone else's.

Removing patch files from this Git checkout does not remove them from an
installed kernel. Build from the clean distro source/T2 base instead of
stacking Falcon onto the previous custom kernel.

The optional `system/systemd/30-mbp161-lid-safety.conf` remains as a separately
reviewed user preference: it makes logind ignore lid closure. Falcon does not
require it, this repository no longer installs it, and its old sleep claims
must not be used as evidence that Falcon suspend works. Decide explicitly
whether to keep an already installed copy.
