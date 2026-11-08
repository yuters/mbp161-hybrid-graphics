# Patch review — 2026-09-27

Reviewed GitHub `main` at
[`ec2d6f0`](https://github.com/yuters/mbp161-hybrid-graphics/commit/ec2d6f08fe0292c4a6402c4ab19f9fed72b981b4),
which matched the clean local checkout. GitHub had no pull requests and one
closed issue. [Issue 1](https://github.com/yuters/mbp161-hybrid-graphics/issues/1)
reports another machine using the retired `e77b03f` series, not independent
validation of Falcon. No changes were posted to other projects during this
review.

## Where the patches stand

| Patch | Scope and evidence | Remaining work |
|---|---|---|
| Kernel 0001, Falcon | Opt-in, exact Apple Navi14 board; signed payload is hash-checked by the extractor; short four-level UCLK transition test; subsequently used on 7.2.6 | Repeated cold boots and transitions under load, other boards, actual hybrid switching |
| Kernel 0002, NCM | `05ac:8233` data alternate closed before S3 and restored afterwards; tested on the reference machine | Repeated cycles, disconnect/abort coverage; compare with BCE reset-resume below |
| Kernel 0003, BCE S4 | Transport rebuild, DMA queue teardown, retained audio card and deferred playback notifications | Initial revision: five restores; loader-teardown revision: one; teardown/audio revision: one. These are different revisions, not seven tests of current code. Failure paths remain below |
| Kernel 0004, Apple AV adapter | Disables DSC and 4:2:2 for DP-HDMI branch OUI `00-10-fa`, name `cHDMIb`; one Dell S2722QC works at 4K60 4:2:0 and 4K30 RGB | Other firmware/adapters/displays and external-display recovery across sleep. The code matches branch identity, not USB VID/PID or firmware version |
| Boot 0001, Limine reserve | EFI chooses the firmware reserve before conventional-memory claiming; tested with Limine 12.8.0 | Other firmware and loader versions; no replacement established by this review |

The active setup is AMD-primary Falcon. The repository name should not be
read as a claim that runtime hybrid graphics is implemented here.

## Findings and changes

1. **Fixed: audio probe cleanup could use an uninitialized rwsem.** Patch
   0003 added unconditional transport cleanup once a BCE client exists, but
   initialized the lock only after device creation, PCI mappings and workqueue
   allocation. A failure in those steps reaches `down_write()` on an
   uninitialized lock. Initialize transport locks immediately after allocating
   the audio device, before acquiring the client. This changes error handling,
   not the S4 transport protocol.
2. **Fixed: the documented external-display build omitted patch 0004.** The
   helper applied only 0001 even though the display instructions referred to
   it for a combined build. `--with-apple-av-adapter` now explicitly selects
   both patches. Each is applied without fuzz and without interactive prompts;
   the manifest records both hashes. The default remains Falcon alone.
3. **Fixed: validation claims were inconsistent.** The README still called
   external displays and graphics sleep unvalidated, and the display guide
   omitted the later S4 run using amdgpu `7135E5DE`. The docs now distinguish
   those observations from broader reliability and from today's unbooted fix.
4. **Open, high severity: failed queue revocation does not protect URB buffers.**
   `bce_vhci_destroy_transfer_queue()` calls
   `bce_vhci_transfer_queue_giveback()` and removes pending URBs even when
   `t2bce_core_revoke_firmware_queues()` fails. The ring quarantine protects
   ring allocations, not transfer payloads returned to USB callers. Firmware
   can still own those DMA addresses. A complete fix requires a proven DMA
   fence or a lifetime/ownership redesign across usbcore teardown; skipping
   giveback alone would not establish safe cleanup. Keep this separate from
   the tested successful S4 path. The existing claim that only S3 can reach
   this state was too strong: a mailbox sign-on can fail during S4 teardown too.

## Related work checked online

| Project / source | Overlap | Assessment |
|---|---|---|
| [KAIT2EN status](https://kait2en.org/) and [16,x hybrid commit](https://github.com/kaiT2en/KaiT2en-Fedora/commit/73a1b8e1615b826327d8f5483837f7930ae4f25a) | Advertises 16,1/16,4 runtime GPU switching, power management and suspend as available downstream, dated September 22 | Most relevant parallel graphics effort. The amdgpu runtime-PM patch explicitly includes both models and works with `t2gmux`; it is not this repository's Falcon firmware patch. Evaluate as a separate candidate, not a blind addition to the current setup |
| [KAIT2EN HDA change](https://github.com/kaiT2en/KaiT2en-Fedora/commit/b8b5cc9beeb78aa329b21e18afe14368f6f7f841) | Drops HDA direct-complete because 16,1 amdgpu mode1 reset also resets the audio controller | Relevant reset-ordering evidence for investigating CORB timeouts. The local 7.2.6 source lacks their added `azx_vga_is_powered_off()` early return, so reverting that patch is not a fix to apply here |
| [deqrocks/t2bce PR 8](https://github.com/deqrocks/t2bce/pull/8) | Same post-S3 NCM OUT-credit loss; reset-resumes devices with OUT endpoints so usbcore restores the interface | Open, not merged at review time. Reported tests are on 16,2. Alternative to 0002's pre-sleep interface closure; compare separately before combining |
| [deqrocks/t2bce PR 9](https://github.com/deqrocks/t2bce/pull/9) | Reopens transport/event queues before no-state S3 HCD teardown and propagates drain failures | Open. Relevant to the teardown failure above, but not a replacement for S4 queue reconstruction. Its reported hardware cycle took the stateful branch, so no-state hardware coverage remains missing |
| [T2 delayed-UCLK PR 61](https://github.com/t2linux/linux-t2-patches/pull/61) | Related Apple Navi startup failures | Closed without merge. Latest scope excludes this repo's `020f` board after a post-login hang; not a Falcon replacement |
| [klizas/t2-kernel-patches](https://github.com/klizas/t2-kernel-patches) | Same laptop; AMD power gating, DRAM-clock latency override, Touch Bar and sleep work | Related experiments, not replicated Falcon validation. Do not import latency or power-gating changes without firmware-specific evidence |
| [T2 kernel issue 22](https://github.com/t2linux/kernel/issues/22) | S4 VHCI timeouts and subsequent faults on 15,2 | Independent report of a similar failure class, not a successful test of 0003 |
| [Limine allocator inspected](https://github.com/Limine-Bootloader/Limine/blob/0be17a661423121be1db7c0d596132fe127126bd/common/mm/pmm.s2.c) | Firmware reserve / memory-map handling | Still allocates the 64 MiB reserve internally after map processing; no equivalent EFI-selected reserve was found in that revision |

KAIT2EN was checked at `555f93d09e8b007519ff07f4b0727a809f87cf8e`;
PR 8 at `21221926651b8c9238066b7bc163438d8b9364dc`, PR 9 at
`e00439a532b3f7b5764529ab0c6db907a4404706`. Status claims above are those
of the linked projects, not new measurements on this machine. Searches did
not establish an independent equivalent of the exact Falcon, Apple adapter
or Limine reserve patches; this is not proof that none exists.

## Validation of this review's changes

Completed checks:

- All four kernel patches apply without fuzz to the packaged 7.2.6 source;
  the Limine patch applies without fuzz to its documented `89644f1` base.
- All five BCE modules compile against
  `7.2.6-arch2-Watanare-T2-2-t2` headers, with matching module vermagic.
  The reapplied audio patch produces exactly the source that was compiled.
- The updated helper builds amdgpu with both 0001 and 0004. The resulting
  manifest's module and patch hashes match the actual files.
- A missing adapter source file is rejected noninteractively before make
  starts; no manifest is produced and the input source remains unchanged.
- Five firmware-extraction unit tests pass; Bash syntax, local documentation
  links and `git diff --check` pass.

Both module builds reported a `pahole` version mismatch (installed 131 versus
the kernel's 132), but completed, including BTF generation. No compiler errors
were reported. This is build validation, not proof of load-time compatibility.

Builds use the available packaged 7.2.6 source and matching prepared headers,
in separate output directories. No module, firmware or bootloader is installed
by this review, and no sleep, hibernate or reboot is initiated. Build and unit
checks cannot validate hardware recovery or the remaining DMA failure path.
