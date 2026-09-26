# Hibernation (S4)

Hibernation works on the reference machine with two independent changes:
a T2 BCE driver patch and a Limine loader patch. The initial rebuild revision
passed **5/5 real S4 restores**, the last three from the everyday boot with
the ESP mounted and no one-time boot selection. The current revision also:

- drops the loading kernel's command queues before memory handoff;
- keeps the sound card registered across S4;
- hardens queue teardown (IRQ race, failed unregister);
- fixes a hard-IRQ sleep in audio playback.

It has passed **one real S4 restore**, with the previous apps, input, the
PipeWire speaker sink and sound confirmed. The S3 callbacks are unchanged
except that the audio trigger now handles SUSPEND.

| Patch | Component | What it fixes |
|---|---|---|
| [`kernel/patches/0003-t2bce-hibernate-rebuild-transport.patch`](../kernel/patches/0003-t2bce-hibernate-rebuild-transport.patch) | `t2bce_dma`, `t2bce_core`, `t2bce_vhci`, `t2bce_audio` (+ `t2bce_ave` teardown) | Restored kernel hangs on a T2 transport bridgeOS no longer has |
| [`boot/patches/0001-limine-firmware-selected-reserve.patch`](../boot/patches/0001-limine-firmware-selected-reserve.patch) | Limine 12.8.0 | Image rejected: "Hibernate inconsistent memory map" |

## Why it failed

### Memory map (loader)

After a hibernation power-off, the boot through stock Limine produced an
E820 map with an 8K RAM hole inside an ACPI reclaim region, so the kernel's
map checksum no longer matched the image and it refused to resume. Limine
reserves 64 MiB below 4 GiB for the firmware by allocating it itself,
top-down, after claiming all usable memory. The Apple DXE allocator then
has nowhere for later pool allocations except ACPI reclaim slack. The patch
lets EFI choose where that reserve goes (`AllocateMaxAddress` before the
claim, then `FreePages`), so the map is identical across boots.

Ignoring the checksum instead would restore into a map the kernel knows is
different; that is not used here.

### T2 transport (driver)

The T2 exposes the keyboard, trackpad, Touch Bar, camera, sensors, audio and
the internal Ethernet through BCE queues that bridgeOS owns. The findings
below come from decoding bridgeOS 23P6068 (J152F) and macOS 26.6.2
`IOBufferCopyController` locally; no Apple binary is included here.

- **Sign-on destroys every queue of the host owner.** Setup command 0x0c
  (BootCamp) or 0x0d (macOS) tears down all queues in the host context
  before switching owner; EFI signs on separately as 0x0a.
- **Saved state is keyed by a nonce only the serializer writes.** On
  restore, an equal nonce skips deserialization entirely ("deserialization
  not required"); a different one is rejected. The reply is 0x1a either way,
  so a successful mailbox exchange proves nothing.
- **Wake opcode selects host type.** 0x18 means BootCamp, 0x1b macOS, and
  the type is checked against the saved state. Linux signs on with 0x0c, so
  0x18 is the consistent wake; 0x1b after a 0x0c sign-on would be rejected
  on a full restore.

macOS hibernation works because the EFI booter uses its own owner context
and the host's queues survive untouched. On Linux with an encrypted root,
the image-loading kernel must drive the keyboard for the LUKS prompt, so it
signs on as the host with 0x0c. That destroys the hibernated kernel's
queues and replaces them with its own. The restored kernel then used queue
ids and DMA addresses bridgeOS no longer had, while the loader's queues
could still write into restored memory (`iommu=pt`, physical addresses).

The current Linux initramfs sequence cannot reuse those firmware queues, so
the patch rebuilds them:

1. Before tasks freeze (`PM_HIBERNATION_PREPARE`, and `PM_RESTORE_PREPARE`
   in the image-loading kernel), VHCI removes its HCD, which destroys every
   device's transfer queues, then its event and message queues. Audio
   suspends its streams and releases its queues but keeps the card. The core
   command queues remain registered at this point.
2. Writer `freeze`/`thaw` quiesce the core without a firmware sleep handshake.
   In the loading kernel, `PM_RESTORE_PREPARE` selects a different `freeze`
   path: sign on with 0x0c to discard all host-owner queues before memory is
   replaced. On a failed load, `thaw` rebuilds the command queues before
   client reattachment. A mailbox failure still needs fault-injection testing.
3. The restored kernel's `restore` signs on again with 0x0c, resets the command
   queue rings and re-registers them.
4. After thaw (`PM_POST_HIBERNATION`), VHCI rebuilds its queues and a fresh
   HCD, and the T2 devices re-enumerate. Audio rebuilds its queues, repeats
   the alive handshake, and checks that bridgeOS still describes the devices
   and buffers the card was built from. It then re-arms remote access, and
   userspace re-prepares the suspended streams.

An earlier revision unbound and re-probed the audio device instead. The card
then disappeared while `user.slice` was frozen and came back before
WirePlumber saw the removal. WirePlumber 0.5.17 (`alsa.lua`) handled the
late removal after the re-add, which has the same SPA id, and lost the
speaker node. Keeping the card avoids this. If the check after resume fails,
the driver falls back to that unbind and re-probe, never to a card running on
stale firmware state.

Queue teardown was hardened too:

- **Completion race:** the completion IRQ is synchronized before a
  submission queue is freed.
- **Failed unregister:** the queue stays in quarantine, and nothing is
  submitted until a sign-on revokes every host queue. Clients keep posted
  buffers, including VHCI's URBs, until the unregister succeeds or the revoke
  happens, and the writer refuses to freeze while anything is quarantined.
- **Audio playback lockup:** the playback timer called
  `snd_pcm_period_elapsed()` from hard IRQ on a nonatomic PCM. Any ALSA
  client using period wakeups locked the machine; PipeWire, which does not
  use them, was unaffected. The call now runs from a work item.
- **Earlier fixes:** `t2bce_audio` leaked its registered queues on remove,
  and VHCI freed DMA buffers before unregistering their queue.

## Setup

Both the hibernating boot and the restoring boot must go through the patched
loader, and both kernels need the patched modules. Build against the
**exact** installed kernel, as for Falcon ([install](INSTALL.md)).

1. Apply `0003-t2bce-hibernate-rebuild-transport.patch` to the packaged
   kernel's `drivers/staging/t2bce` and build the whole directory against
   `/usr/lib/modules/$(uname -r)/build`, with `CONFIG_T2BCE_DMA`, `_CORE`,
   `_VHCI`, `_AUDIO` and `_AVE` set to `m`. The DMA queue structures changed,
   so all of the modules must come from the same build.
2. Put the patched dma, core, VHCI and audio modules in the initramfs of the
   boot image (`MODULES+=(t2bce_audio)` for audio). The image-loading kernel
   runs them before the image is read. Audio in the initramfs means an older
   copy on the root filesystem can never be loaded next to the new core.
3. Build Limine 12.8.0 with `0001-limine-firmware-selected-reserve.patch`
   (`./configure --enable-uefi-x86-64 && make`). Install it in its own ESP
   directory with its own `limine.conf` pointing at the boot image, and add
   an EFI boot entry for it **first** in `BootOrder`. Keep the stock Limine
   entry next as the fallback (hold Option at power-on to pick it).
4. Keep Omarchy's `resume=` / `resume_offset=` for the swapfile. The
   everyday command line needs nothing else for S4.

Rebuild after every kernel update; nothing here is tracked by DKMS.

## Validation

| Run | Setup | Result |
|---|---|---|
| 1 | Patched core + VHCI, audio unloaded, instrumented reserve loader | Restored |
| 2 | Core + VHCI + audio, instrumented loader, via `systemctl hibernate` | Restored |
| 3–5 | Everyday setup: clean loader first in `BootOrder`, ESP mounted, no BootNext | 3/3 restored |
| 6 | Loader queue teardown revision, reserve entry for writer and loader, ESP unmounted | Restored; previous apps and input confirmed usable |
| 7 | Current revision (teardown hardening, audio keeps its card), reserve entry | Restored; card kept, speaker sink present, sound and input confirmed |

Runs 1–5: kernel `7.2.6-arch2-Watanare-T2-2-t2`; modules core `07CBD5DD`, VHCI
`D08F6634`, audio `50ABF997`; clean loader SHA-256 `c35430e4…`. Every restore
kept the writer's boot id, logged `hibernate restore: exit status=0`, VHCI
`attach after hibernation: exit status=0` and audio re-bound. Keyboard,
trackpad, Touch Bar, T2 Ethernet, the T2 sound card and its PipeWire sink
came back each time. No T2 transport errors, kernel warnings or FAT
warnings in the logs.

Run 6: same kernel, core `9F39176E`, VHCI `D08F6634`, audio `50ABF997`.
The writer boot ID `5205a13b-b8f8-49c9-9a98-acc82bc06a08` survived restore;
core, VHCI and audio reported successful reattachment. No queue unregister
failures appeared. AMD HDMI audio reported two CORB reset timeouts. The
loader's journal is replaced by the saved image, so its pre-handoff marker
is not present in the restored journal; this test confirms the end-to-end
restore, not an independent capture of the loader's mailbox transaction.
The loader teardown revision has not repeated the daily-entry series or an
aborted image-load test.

Run 7: same kernel, dma `1DC122D0`, core `E9020F90`, VHCI `3499BD86`, audio
`331CAD19` (all in the initramfs), daily amdgpu `7135E5DE`.
- The writer boot ID `5f834534-3ee4-4d3d-b2c6-f339152856fc` survived.
- The kernel logged `transport released, card kept` and `attach after
  hibernation: card kept, status=0`.
- There were no T2 errors, kernel warnings, or WirePlumber ALSA or script
  errors, and the PipeWire T2 speaker sink was present after resume.

A run on the previous audio revision (unbind and re-probe) restored, but
reproduced the WirePlumber sink loss described above.

## Not covered

- The current revision has one real restore; the daily-entry series is not
  repeated yet.
- Queue unregister failure has never occurred on hardware. Its handling
  (quarantine, revoke, writer refusal) is covered only by source-level fault
  injection. If the revoke cannot run (inside a PM callback, or with the
  mailbox paused), URBs already unlinked by usbcore are still handed back; only
  S3 paths reach that state.
- `t2bce_ave` (video encoder) has no rebuild path yet; it is not loaded on
  the reference machine.
- The AMD dGPU HDMI audio function logs `CORB reset timeout` after some
  restores; unrelated to T2, not investigated.
- `hid-appletb-kbd` sometimes logs `Failed to get backlight device` when the
  T2 devices re-enumerate (also after a plain module reload): enumeration
  order, not this patch.
- One reference machine and one kernel release.
