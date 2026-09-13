#!/usr/bin/env bash
# Build only amdgpu from a separate copy of the exact installed-kernel source.
set -euo pipefail
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    echo "Usage: $0 EXACT_KERNEL_SOURCE NEW_OUTPUT_DIRECTORY [KERNEL_RELEASE]"
    echo 'Preserve the distro T2 patches in the source. Default kernel: uname -r.'
    echo 'Builds in the output directory; does not install or change the input tree.'
    exit 0
fi
[[ $# -ge 2 && $# -le 3 ]] || { echo "See $0 --help" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_tree=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
release=${3:-$(uname -r)}
headers="/usr/lib/modules/$release/build"
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
patch_file="$repo/kernel/patches/0001-amdgpu-apple-falcon.patch"
patch --directory="$output/source" -p1 --forward --fuzz=0 --dry-run < "$patch_file"
patch --directory="$output/source" -p1 --forward --fuzz=0 < "$patch_file"
make -C "$headers" M="$output/source/drivers/gpu/drm/amd/amdgpu" \
    KCFLAGS="-I$output/source/drivers/gpu" -j"${JOBS:-2}" modules 2>&1 | tee "$output/build.log"
objcopy --strip-debug "$output/source/drivers/gpu/drm/amd/amdgpu/amdgpu.ko" "$output/amdgpu.ko"
[[ $(modinfo -F vermagic "$output/amdgpu.ko") == "$release "* ]] || { echo 'Built module release mismatch' >&2; exit 1; }
python3 - "$output" "$release" "$patch_file" <<'PY'
import hashlib, json, pathlib, subprocess, sys
out=pathlib.Path(sys.argv[1])
manifest=dict(kernel=sys.argv[2],
              module_sha256=hashlib.sha256((out/'amdgpu.ko').read_bytes()).hexdigest(),
              patch_sha256=hashlib.sha256(pathlib.Path(sys.argv[3]).read_bytes()).hexdigest(),
              module_srcversion=subprocess.check_output(['modinfo','-F','srcversion',str(out/'amdgpu.ko')],text=True).strip())
(out/'module-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
printf 'Built %s/amdgpu.ko; nothing installed. See docs/INSTALL.md.\n' "$output"
