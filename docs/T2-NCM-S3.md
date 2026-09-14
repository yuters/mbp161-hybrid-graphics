# T2 NCM after deep sleep

On the reference MacBookPro16,1, Falcon graphics already resumed from
deep sleep. The remaining failure was the T2 internal USB Ethernet
(`cdc_ncm` on `usb 7-1`, `05ac:8233`, `enp4s0f1u1`): the interface stayed
UP with carrier, RX froze, and TX hit `NETDEV WATCHDOG`. Wi-Fi (separate
PCI) kept working. The keyboard on `usb 7-5` recovered by re-enumeration.
NCM never disconnected.

This is independent of the Falcon amdgpu patch. Use
[kernel/patches/0002-cdc-ncm-apple-t2-s3.patch](../kernel/patches/0002-cdc-ncm-apple-t2-s3.patch)
on the same 7.2.4 T2 kernel; do not bundle controller-PM VHCI or
`usb_reset_device`.

## Cause

Stateful BCE restore leaves the CDC NCM **data function** wedged in
firmware. Control transfers on EP0 still work. Firmware then sends no
new bulk OUT `TRANSFER_REQUEST`s, and newly posted IN buffers never
complete.

Isolated VHCI experiments did not reopen it: leftover OUT grants, DMA
flush, `ENDPOINT_RESET` (0x44), and `ENDPOINT_DESTROY`/`CREATE` of the
existing pipes all still hung. A userspace USB reset of `7-1` recovered
NCM, as did unbind/rebind of `cdc_ncm` **without** a port reset (same USB
address). Rebind works because probe toggles the data altsetting 0 then 1.

## Fix

For `05ac:8233` on **system** suspend only (not autosuspend), after USB
resume returns, SET_INTERFACE the data interface to alt 0, wait 10–20 ms,
then alt 1, then `usbnet_resume` so URBs start on the new pipes. The
toggle is deferred on a workqueue; doing it inside `cdc_ncm_resume`
recovers NCM but logs `parent should not be sleeping`.

The deferred work takes a `usb_get_dev()` reference to the parent device
and `usb_lock_device()`s it *before* reading `usb_get_intfdata()`, so a
concurrent disconnect (unplug/`rmmod`/shutdown) cannot free the usbnet
state while the work is toggling.

## Validation (13 September 2026)

Same machine and kernel as the Falcon module (`6AA8D5F52AD5DB85D2CFADC`).
Stock `t2bce_vhci` `B8FCE43DDFBFB6770941DC0`. One deep/S3 cycle per image.

| Image | `cdc_ncm` srcversion | Result |
|---|---|---|
| Inline SET_INTERFACE | `F15001FEFD548EF35879A88` | NCM TX advanced, 0 errors; two `parent should not be sleeping` warnings |
| Deferred SET_INTERFACE | `964E35070A50E7AD7BD2970` | Same recovery, no those warnings |
| Deferred + disconnect-race fix | `C8EB8EC2B9FF9EA3D620E21` | Same recovery; work now holds a udev ref + lock. Re-tested 13 Sep: TX 91 → 240 pkts, 0 errors, 0 watchdog, SMU resumed |

On the deferred boot, alt 0 and alt 1 both returned 0. After wake, TX
continued to increase (3492 → 10524 bytes in the capture window) with 0
errors and no watchdog. RX stayed at 96 bytes / 1 packet, which is the
idle internal-link baseline, not a freeze.

One cycle on one machine. Not a claim about repeated sleep, other T2
boards, or Touch ID.

## Build

Against the installed kernel headers, from a tree with `cdc_ncm.c` patched:

```sh
make -C /usr/lib/modules/$(uname -r)/build M=/path/to/cdc_ncm_dir modules
```

`M=` needs the usual out-of-tree `Makefile` (`obj-m += cdc_ncm.o`) and a
copy of `drivers/net/usb/cdc_ncm.c` with the patch applied. Only this
module changes. A distro `linux-t2` upgrade replaces it unless the patch
is in that package.
