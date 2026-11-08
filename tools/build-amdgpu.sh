#!/usr/bin/env bash
# Build only amdgpu from a separate copy of the exact installed-kernel source.
set -euo pipefail
with_apple_av_adapter=false
with_hybrid=false
while [[ ${1:-} == --with-* ]]; do
    case "$1" in
        --with-apple-av-adapter) with_apple_av_adapter=true ;;
        --with-hybrid) with_hybrid=true ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    echo "Usage: $0 [--with-apple-av-adapter] [--with-hybrid] EXACT_KERNEL_SOURCE NEW_OUTPUT_DIRECTORY [KERNEL_RELEASE]"
    echo 'Preserve the distro T2 patches in the source. Default kernel: kernel/target-release.'
    echo 'Always applies Falcon (0001); --with-apple-av-adapter adds patch 0004.'
    echo 'Hybrid adds KAIT2EN runtime PM (0005); also build the pinned t2gmux with build-t2gmux.sh.'
    echo 'Builds in the output directory; does not install or change the input tree.'
    echo 'KERNEL_HEADERS may point to extracted matching headers for a staged kernel.'
    exit 0
fi
[[ $# -ge 2 && $# -le 3 ]] || { echo "See $0 --help" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_tree=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
release=${3:-$(cat "$repo/kernel/target-release")}
headers=${KERNEL_HEADERS:-/usr/lib/modules/$release/build}
if "$with_hybrid"; then
    python3 - "$repo/kernel/hybrid-upstream.json" "$release" <<'PY'
import json, pathlib, sys
pin = json.loads(pathlib.Path(sys.argv[1]).read_text())
if pin['kernel_release'] != sys.argv[2]:
    raise SystemExit('Review the hybrid patches for this target kernel before building')
PY
fi
# Kbuild splits compiler include flags on whitespace.
[[ ! "$output" =~ [[:space:]] ]] || { echo 'Output path must not contain whitespace' >&2; exit 1; }
[[ ${JOBS:-2} =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 1; }
[[ -f "$source_tree/drivers/gpu/drm/amd/amdgpu/Makefile" ]] || { echo 'Missing AMD source' >&2; exit 1; }
[[ -f "$headers/Module.symvers" && -f "$headers/include/config/kernel.release" ]] || { echo 'Missing matching prepared kernel headers' >&2; exit 1; }
[[ $(cat "$headers/include/config/kernel.release") == "$release" ]] || { echo 'Header release mismatch' >&2; exit 1; }
[[ ! -e "$output" ]] || { echo 'Output must not already exist' >&2; exit 1; }
case "$output/" in "$source_tree/drivers/gpu/"*) echo 'Output must be outside the copied GPU source' >&2; exit 1 ;; esac
for command in make patch objcopy modinfo python3; do command -v "$command" >/dev/null; done
mkdir -p -- "$output/source/drivers"
cp -a --reflink=auto -- "$source_tree/drivers/gpu" "$output/source/drivers/"
patch_files=("$repo/kernel/patches/0001-amdgpu-apple-falcon.patch")
if "$with_apple_av_adapter"; then
    patch_files+=("$repo/kernel/patches/0004-drm-amd-display-apple-usb-c-av-adapter.patch")
fi
if "$with_hybrid"; then
    patch_files+=("$repo/kernel/patches/0005-amdgpu-apple-gmux-runtime-pm.patch")
fi
for patch_file in "${patch_files[@]}"; do
    patch --directory="$output/source" --batch -p1 --forward --fuzz=0 --dry-run < "$patch_file"
    patch --directory="$output/source" --batch -p1 --forward --fuzz=0 < "$patch_file"
done
make -C "$headers" M="$output/source/drivers/gpu/drm/amd/amdgpu" \
    KCFLAGS="-I$output/source/drivers/gpu" -j"${JOBS:-2}" modules 2>&1 | tee "$output/build.log"
objcopy --strip-debug "$output/source/drivers/gpu/drm/amd/amdgpu/amdgpu.ko" "$output/amdgpu.ko"
[[ $(modinfo -F vermagic "$output/amdgpu.ko") == "$release "* ]] || { echo 'Built module release mismatch' >&2; exit 1; }
python3 - "$output" "$release" "${patch_files[@]}" <<'PY'
import hashlib, json, pathlib, subprocess, sys
out=pathlib.Path(sys.argv[1])
manifest=dict(kernel=sys.argv[2],
              module_sha256=hashlib.sha256((out/'amdgpu.ko').read_bytes()).hexdigest(),
              patch_sha256=hashlib.sha256(pathlib.Path(sys.argv[3]).read_bytes()).hexdigest(),
              patches=[dict(name=pathlib.Path(p).name,
                            sha256=hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest())
                       for p in sys.argv[3:]],
              module_srcversion=subprocess.check_output(['modinfo','-F','srcversion',str(out/'amdgpu.ko')],text=True).strip())
(out/'module-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
printf 'Built %s/amdgpu.ko; nothing installed. See docs/INSTALL.md.\n' "$output"
