# Hibernation (S4)

Hibernation works on the reference machine with two independent changes:
a T2 BCE driver patch and a Limine loader patch. **5/5 real S4 restores**
passed, the last three as plain `systemctl hibernate` from the everyday boot
with the ESP mounted and no one-time boot selection. Suspend-to-RAM (S3) is
unchanged by either patch.

| Patch | Component | What it fixes |
|---|---|---|
| [`kernel/patches/0003-t2bce-hibernate-rebuild-transport.patch`](../kernel/patches/0003-t2bce-hibernate-rebuild-transport.patch) | `t2bce_core`, `t2bce_vhci`, `t2bce_audio` | Restored kernel hangs on a T2 transport bridgeOS no longer has |
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

No saved state can survive that, so the patch rebuilds instead:

1. Before tasks freeze (`PM_HIBERNATION_PREPARE`, and `PM_RESTORE_PREPARE`
   in the image-loading kernel), VHCI removes its HCD, which destroys every
   device's transfer queues, then its event and message queues. Audio
   unbinds its device. Only the core command queues remain, with nothing
   posted for bridgeOS to write into.
2. `freeze`/`thaw` quiesce the core without a firmware sleep handshake.
3. `restore` signs on again with 0x0c, which drops the loader's queues,
   resets the command queue rings and re-registers them.
4. After thaw (`PM_POST_HIBERNATION`), VHCI rebuilds its queues and a fresh
   HCD, and the T2 devices re-enumerate; audio probes again.

The audio unbind never waits for userspace: `systemd-sleep` freezes
`user.slice` (PipeWire included) before the kernel notifiers run, so
`remove()` disconnects the card and frees it once the last user closes it,
as USB audio does on unplug. The patch also fixes two teardown bugs found on
the way: `t2bce_audio` leaked its registered queues on remove (receive
buffers still posted, completion callback into the module), and VHCI freed
DMA buffers before unregistering their queue.

## Setup

Both the hibernating boot and the restoring boot must go through the patched
loader, and both kernels need the patched modules. Build against the
**exact** installed kernel, as for Falcon ([install](INSTALL.md)).

1. Apply `0003-t2bce-hibernate-rebuild-transport.patch` to the packaged
   kernel's `drivers/staging/t2bce` and build the three modules against
   `/usr/lib/modules/$(uname -r)/build` (VHCI and audio with the patched
   core's `Module.symvers` in `KBUILD_EXTRA_SYMBOLS`).
2. Put the patched core and VHCI in the initramfs of the boot image: the
   image-loading kernel runs them before the image is read. On the reference
   machine they are also installed in `/usr/lib/modules/<release>/updates/`
   so audio (loaded from the root filesystem) is patched too. This is
   deliberate here, unlike the isolated Falcon test image: every entry
   should get the teardown fixes, and S3 paths are unchanged.
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

Kernel `7.2.6-arch2-Watanare-T2-2-t2`; modules core `07CBD5DD`, VHCI
`D08F6634`, audio `50ABF997`; clean loader SHA-256 `c35430e4…`. Every restore
kept the writer's boot id, logged `hibernate restore: exit status=0`, VHCI
`attach after hibernation: exit status=0` and audio re-bound. Keyboard,
trackpad, Touch Bar, T2 Ethernet, the T2 sound card and its PipeWire sink
came back each time. No T2 transport errors, kernel warnings or FAT
warnings in the logs.

## Not covered

- `t2bce_ave` (video encoder) has no rebuild path yet; it is not loaded on
  the reference machine.
- The AMD dGPU HDMI audio function logs `CORB reset timeout` after some
  restores; unrelated to T2, not investigated.
- `hid-appletb-kbd` sometimes logs `Failed to get backlight device` when the
  T2 devices re-enumerate (also after a plain module reload): enumeration
  order, not this patch.
- One reference machine and one kernel release.
