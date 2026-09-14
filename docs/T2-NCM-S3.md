# T2 NCM after deep sleep

On the reference MacBookPro16,1, Falcon graphics resumed from deep
sleep while the T2 internal USB Ethernet (`cdc_ncm` on `usb 7-1`,
`05ac:8233`, `enp4s0f1u1`) stayed UP with carrier, froze RX, and hit
`NETDEV WATCHDOG`. Wi-Fi kept working. The keyboard on `usb 7-5`
recovered by re-enumeration. NCM never disconnected.

Independent of Falcon. Do not bundle controller-PM VHCI or
`usb_reset_device`.

## Cause

Linux usbnet suspends URBs but **leaves the CDC NCM data alternate at 1**
across system sleep. Native `AppleUSBNCMData` on 05ac:8233 (also 8600)
sets that alternate to **0 before** root-domain sleep and enables it
after wake.

That is the host bug. After S3 with alt 1 still selected, EP0 still
worked and bulk did not (no new OUT `TRANSFER_REQUEST`s, IN buffers
never completed). VHCI grant/flush/reset/recreate experiments failed.
USB reset and unbind/rebind recovered NCM only because they re-init the
data interface after the fact.

A post-resume 0→1 toggle was the same recovery. It is **not** in this
tree. The patch closes alt 0 **before** sleep, which is the native
sequence.

## Patch

[kernel/patches/0002-cdc-ncm-t2-sleep-lifecycle.patch](../kernel/patches/0002-cdc-ncm-t2-sleep-lifecycle.patch)

On `PM_SUSPEND_PREPARE`: runtime-PM get, quiesce usbnet, SET_INTERFACE
data alt 0. USB's own suspend/resume then run with usbnet already
stopped. On `PM_POST_SUSPEND`: SET_INTERFACE back to the saved
alternate, usbnet_resume, runtime-PM put.

Reference module `cdc_ncm` `17909571FF2AFE1A0781AEB`, stock VHCI. One
deep cycle after the lock/restore review: alt 0 before BCE save, alt 1
after resume, 6/6 unicast replies to the T2 peer, 0 TX errors, no
watchdog. An earlier build of the same design passed two cycles
(`F5DA9A6DDAE6EC24DC7CDD4`).

Native `configureData` extras (CRC mode, NTB format, datagram limit,
NTB input size) are not replayed. They were not required to stop the
hang on the traffic this machine uses. **Do not add them, and do not
run another S3, unless a new failure shows they are needed.**

The global PM notifier and extra usbnet `suspend_count` are how Linux
does SET_INTERFACE while the device is still awake. That is
implementation, not a second bug. Changing it is a new design and would
need a new S3; there is no current reason to.

Hibernation (`PM_HIBERNATION_*`) is out of scope. Other T2 products are
untested.

## Build

```sh
make -C /usr/lib/modules/$(uname -r)/build M=/path/to/cdc_ncm_dir modules
```

`M=` needs `obj-m += cdc_ncm.o` and patched `drivers/net/usb/cdc_ncm.c`.
A distro `linux-t2` upgrade replaces a locally installed module unless
this patch is in that package.
