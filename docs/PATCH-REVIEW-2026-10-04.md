# Patch assessment — 2026-10-04

This records the assessment before implementation. See [the subsequent
7.2.8 build](HYBRID.md) for completed rebases, build checks and test-image scope.

## Local and published state

GitHub main remains at
[`ec2d6f0`](https://github.com/yuters/mbp161-hybrid-graphics/commit/ec2d6f08fe0292c4a6402c4ab19f9fed72b981b4).
The September review edits and this assessment are local, uncommitted work.
The running daily image is `7.2.6-arch2-Watanare-T2-2-t2`; installed kernel
and headers are `linux-t2 7.2.8.arch1-1`. The user approved changing the next
build target to `7.2.8-arch1-Watanare-T2-1-t2`; `kernel/target-release` now
records it. The 7.2.7 headers are no longer installed.

The previous candidate did finish compiling all eight modules for 7.2.7:
amdgpu, cdc_ncm, t2gmux and the five BCE modules. No assembled test UKI or
hardware validation was found. It predates important changes below and
should be refreshed before testing. No 7.2.8 candidate build is claimed.

## KAIT2EN: refresh the hybrid foundation

The inspected revision is
[`ed5a361`](https://github.com/kaiT2en/KaiT2en-Fedora/commit/ed5a3613a49399a8b426850cdde8c3eaf43f71e9).
There are [69 commits since our previous source pin](https://github.com/kaiT2en/KaiT2en-Fedora/compare/555f93d09e8b007519ff07f4b0727a809f87cf8e...ed5a3613a49399a8b426850cdde8c3eaf43f71e9),
including unrelated audio, Touch Bar and iMac work. Relevant source changes:

- [Initialize inactive AMD eDP correctly and retire the HDA override](https://github.com/kaiT2en/KaiT2en-Fedora/commit/a4b4b5ac26bc65511bcb67b10b8f0e8ee8492735).
  Display-core initialization now marks eDP disconnected when Intel owns the
  display, while retaining connector setup.
- [Avoid POWER_CHANGING for GMUX runtime suspend](https://github.com/kaiT2en/KaiT2en-Fedora/commit/64bce71219c7297fc0b112538cf72b808ebda22f).
  This addresses compositor reopen failures.
- [Unload MP1 before runtime power-off](https://github.com/kaiT2en/KaiT2en-Fedora/commit/2b6e7c79c3d86813fa89f59b5177c7cad8489ca6).
  Review and test this together with Falcon's firmware initialization; a
  successful compile will not establish safe repeated power cycles.
- [Revise the 16,x power-up sequence and interrupt handling](https://github.com/kaiT2en/KaiT2en-Fedora/commit/65af65f071419a7e44e21ed63408c0dc8438a825).
  Current t2gmux lets PWRD perform power-up, enforces a minimum off interval,
  serializes power operations and uses a direct GPE handler with deferred work.
- [Avoid PCI-core bridge suspension conflicts](https://github.com/kaiT2en/KaiT2en-Fedora/commit/398dd080cb1f382b975b133ec42394649eb9cccc)
  and [guard config access during PWRD](https://github.com/kaiT2en/KaiT2en-Fedora/commit/8f32b9c257d6d7ea05fb1f4a5a3735b9f99dcee7).
  These address races between GMUX rail control, bridge power management and
  userspace PCI access. They do not establish that our machine is validated.

KAIT2EN remains the more complete basis for Intel scanout plus AMD offload
and idle power-off. Falcon addresses Apple-specific AMD firmware/UCLK
behavior and is not replaced by these changes. The combination still needs
testing on this 16,1. Do not revive the retired HDA workaround from older
instructions.

## Packaged BCE changes alter the rebase

The installed package's `.BUILDINFO` PKGBUILD SHA-256 matches the retrieved
7.2.8 recipe: `ffcb5b6e798617ba59df09bb4399279c1d77bd0268e9e11ad7a8ad569fb16e36`.
It selects T2 patch revision
[`65fdd4d`](https://github.com/t2linux/linux-t2-patches/tree/65fdd4d492d7e219a05742ce4768f16e5ba4f976).
Its BCE patch is byte-identical (Git blob
`49308c443e1359a51b0f645e528b2d23b8ae1f7d`) to the
[September 28 update](https://github.com/t2linux/linux-t2-patches/commit/6780d522fc19bde5230a1bdef94672d26f0cfc2d).

That source includes stateful USB reset-resume handling, no-state transport
preparation/error propagation, and substantial PCM workqueue/timing changes.
Related [PR 8](https://github.com/deqrocks/t2bce/pull/8) and
[PR 9](https://github.com/deqrocks/t2bce/pull/9) remain open in their source
repository; that status does **not** mean their approaches are absent from
the packaged kernel. Assess shipped source, not PR status alone.

Reconstructing the packaged BCE source and dry-running our patch 0003 with
`patch --batch --fuzz=0 --dry-run -p1` produces **25 failed hunks across nine
files**. Audio, DMA queue, core and VHCI changes require semantic review.
The new core PM table still has only prepare/suspend/resume/complete, with
no freeze/thaw/poweroff/restore callbacks: it is not an S4 replacement.

Our previously identified failure path also remains an open review item:
returning URBs after both queue unregister and firmware revoke fail can
expose buffers to DMA. Quarantining queue rings alone does not protect those
buffers. A rebase must preserve explicit failure handling and must not claim
this concern solved merely because upstream changed teardown.

| Component | Next action |
| --- | --- |
| 0001 Falcon | Rebase/build on exact 7.2.8 source; inspect MP1 unload/resume interaction with refreshed KAIT2EN amdgpu. |
| 0002 T2 NCM | Compare stock packaged reset-resume against our pre-sleep interface closure. Avoid carrying both without an A/B result. |
| 0003 BCE S4 | Rebase retained S4 transport/loader handoff logic onto packaged BCE; reconcile audio lifetime and teardown before building all five modules together. |
| 0004 Apple AV adapter | Retain pending 7.2.8 application/build and external-display tests; no verified replacement found in this review. |
| t2gmux + amdgpu runtime PM | Replace the September 26 candidate sources with a pinned reviewed revision. |
| Limine reserve | Retain the working recovery loader; no equivalent change found in the allocator history checked for this week. |

## Keep Titan Ridge experiments separate

The [current testing series](https://github.com/kaiT2en/KaiT2en-Fedora/tree/ed5a3613a49399a8b426850cdde8c3eaf43f71e9/patches/currently-testing/titan-ridge-runtime-pm)
adds ACPICA bridge bus-number handling and Apple RTPC power handling for
Thunderbolt NHI and xHCI. Its stated motivation includes incorrect PCI config
access after D3cold and long power-up delays on 16,1. It is relevant to power
consumption and docking, but newly published experimental work.

The ACPICA change cannot be delivered by our module-only build: the installed
kernel has `CONFIG_ACPI=y`. Evaluate this series later with a separate full
kernel candidate, after establishing the hybrid baseline.

## Implementation and validation order

1. Reconstruct exact 7.2.8 + Arch + pinned T2 sources and preserve input hashes.
2. Refresh/rebase KAIT2EN amdgpu and t2gmux; reconcile Falcon and adapter patches.
3. Rebase BCE S4 separately, removing duplicated mechanisms only after source
   review; test whether packaged USB reset-resume makes 0002 unnecessary.
4. Build all selected modules against 7.2.8 headers and record their hashes,
   vermagic and source provenance. Assemble and inspect an isolated UKI.
5. Preserve the working daily/recovery boot entries. Validate Intel panel,
   AMD render offload, repeated AMD idle/wake, external hotplug and 4K60.
   Then test S3, audio/NCM recovery and S4, retaining logs for each cycle.

This assessment changed the build target and documentation only. It did not
install modules, alter EFI variables or boot defaults, or run hardware power
transition tests.
