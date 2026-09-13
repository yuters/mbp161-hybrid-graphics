# Build and stage Falcon support

Start with a working Omarchy install and retain its current recovery boot
entry. This procedure builds **only amdgpu**, not a complete kernel. It does
not use the previous `install.sh`, which installed an incompatible workaround
stack. Existing users should read [migration](MIGRATION.md) first.

The verified kernel is `7.2.4-arch1-Watanare-T2-1-t2`. Other kernels require
source/ABI review and their own build. Matching the version string alone is
insufficient: preserve the distro's configuration and T2 patches.

## 1. Extract locally

Obtain the uncompressed `SystemKernelExtensions.kc` from your own macOS
installation. The verified payload was found in macOS 26.6.2 (25G83); another
collection is accepted only if it contains the identical signed payload.
No APFS mount, macOS download or firmware installation is automated here.

From the repository directory:

```sh
mkdir -p build
zstd -dc /usr/lib/firmware/amdgpu/navi14_smc.bin.zst > build/navi14_smc.bin
python3 tools/extract-firmware.py /path/to/SystemKernelExtensions.kc \
    build/navi14_smc.bin build/navi14_falcon_smc.bin > build/firmware-manifest.json
```

If the installed template is already uncompressed, copy that file to
`build/navi14_smc.bin` instead. Both inputs are hash checked against the
[verified pair](VALIDATION.md#build-and-firmware-checks). Unknown versions are
rejected. Do not weaken the checks to make a different image pass. Extraction
refuses to overwrite an existing output file.

## 2. Build the module

Obtain the **exact source and T2 changes for the installed kernel**, plus its
matching prepared headers, compiler and normal kernel module build tools.
Do not use the old five-patch repository kernel or an experimental source tree
containing clock pins, alternate loaders or suspend bypasses.

```sh
JOBS=6 tools/build-amdgpu.sh /path/to/exact-kernel-source build/falcon-module
```

The helper copies GPU sources to the output directory, applies the Falcon
patch without fuzz, and builds against `/usr/lib/modules/$(uname -r)/build`.
It preserves the input tree. Results include `amdgpu.ko`, `build.log` and
`module-manifest.json`. It does not install anything or sign the module.
Use the system's module-signing procedure if signature enforcement is enabled.
A distro kernel update requires a compatible rebuild; no DKMS integration is
claimed here.

## 3. Create an isolated test image

Use a separate module root and a separate UKI, as in the reference test. Do
not put an experimental module in global `updates/` and call the other menu
entries stock: entries that load modules from that directory would use it too.

These staging commands assume the usual Omarchy `/usr/lib/modules` layout:

```sh
release=$(uname -r)
mkdir -p build/module-root/usr/lib/modules
ln -s usr/lib build/module-root/lib
cp -a --reflink=auto "/usr/lib/modules/$release" build/module-root/usr/lib/modules/
```

Inspect the copied tree for locally installed overrides (including `updates/`
and `extra/`). Remove conflicting **amdgpu overrides from this staging copy**;
keep other required modules. Replace its packaged amdgpu file with
`build/falcon-module/amdgpu.ko`, keeping exactly one candidate amdgpu module,
then run `depmod -b "$PWD/build/module-root" "$release"`. Check that
`modinfo -b "$PWD/build/module-root" -k "$release" -n amdgpu` resolves to it.
Do not change the live module tree during this procedure.

Prepare a private mkinitcpio configuration that preserves your existing
storage/encryption, keyboard, T2 and other required hooks. An explicit `-c`
configuration does not automatically source the normal configuration drop-ins;
include their effective settings. Add `amdgpu` to `MODULES` so the candidate
loads before switching to the real root. Use a local final build hook with:

```sh
build() {
    add_file /absolute/path/to/build/navi14_falcon_smc.bin \
        /usr/lib/firmware/amdgpu/navi14_falcon_smc.bin
}
```

That embeds the extracted file at its expected path without replacing the
installed firmware. If using `mkinitcpio -D` for the custom hook directory,
also include `/etc/initcpio` and `/usr/lib/initcpio`: `-D` replaces the default
hook search path rather than merely appending to it.

Prepare the candidate command line from your working entry, preserving all
root, encryption and machine-specific arguments. Select `amdgpu.apple_falcon=1`;
remove the older `amdgpu.smu_alt_smc=falcon` option and forced-Intel/clock-pin
options from this candidate. With the old custom gmux patch still compiled in,
removing `force_igd=1` alone is insufficient; use the clean distro baseline.

Build the UKI with the matching kernel image and staged module root:

```sh
sudo mkinitcpio -r "$PWD/build/module-root" -k "$release" \
    --kernelimage "/usr/lib/modules/$release/vmlinuz" \
    -c /path/to/private-mkinitcpio.conf --cmdline /path/to/falcon.cmdline \
    -D /path/to/custom-initcpio -D /etc/initcpio -D /usr/lib/initcpio \
    --nopost -U "$PWD/build/omarchy-falcon.efi"
```

Before installing, extract the UKI sections (`objcopy --dump-section`) and
inspect its initrd (`lsinitcpio`). Verify exact kernel, module, firmware and
command-line contents against the intended files. Create a recovery image
embedding the packaged stock module as well. Intel scanout can be a recovery
choice; it is not part of the Falcon fix.

Back up the Limine menu, copy the verified UKI to a new path under
`/boot/EFI/Linux/`, and append a separate EFI entry following your existing
menu format and integrity-hash policy. Preserve the working default. Machine
UUIDs, an encrypted-root command line, boot-menu defaults and binary images
from the reference machine are deliberately not supplied as generic files.

## 4. Verify the boot

Check the loaded module against **your build's** manifest, the firmware
version/interface, and the successful `Falcon UCLK rule initialized (0x4b, 1)`
log. Check that AMD's internal eDP connector is enabled and DPM is `auto`.

```sh
cat /sys/module/amdgpu/srcversion
journalctl -k -b --no-pager | rg 'Falcon|smu.*version'
cat /sys/bus/pci/devices/0000:03:00.0/power_dpm_force_performance_level
cat /sys/bus/pci/devices/0000:03:00.0/hwmon/hwmon*/freq2_input
```

Follow [validation](VALIDATION.md) to distinguish a working 750-MHz desktop
from a tested intermediate transition. Save work before deliberate transition
or suspend tests. Avoid an intermediate maximum while a live display requires
750 MHz; restore `auto` before bringing the display back on. The previous
blanket instruction to never use `auto` described a different firmware setup.
