#!/usr/bin/env bash
# Build only the reviewed, pinned KAIT2EN GMUX source. Never install globally.
set -euo pipefail
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    echo "Usage: $0 KAIT2EN_SOURCE NEW_OUTPUT_DIRECTORY [KERNEL_RELEASE]"
    echo 'Checks kernel/hybrid-upstream.json; default kernel: kernel/target-release.'
    echo 'KERNEL_HEADERS may point to extracted matching headers for a staged kernel.'
    exit 0
fi
[[ $# -ge 2 && $# -le 3 ]] || { echo "See $0 --help" >&2; exit 2; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_tree=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
release=${3:-$(cat "$repo/kernel/target-release")}
headers=${KERNEL_HEADERS:-/usr/lib/modules/$release/build}
[[ ! "$output" =~ [[:space:]] ]] || { echo 'Output path must not contain whitespace' >&2; exit 1; }
[[ ${JOBS:-2} =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 1; }
[[ ! -e "$output" ]] || { echo 'Output must not already exist' >&2; exit 1; }
[[ -f "$headers/Module.symvers" ]] || { echo 'Missing prepared kernel headers' >&2; exit 1; }
[[ $(cat "$headers/include/config/kernel.release") == "$release" ]] || { echo 'Header release mismatch' >&2; exit 1; }
python3 - "$repo/kernel/hybrid-upstream.json" "$source_tree" "$release" <<'PY'
import hashlib, json, pathlib, sys
pin = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = pathlib.Path(sys.argv[2]) / pin['t2gmux_source']
if pin['kernel_release'] != sys.argv[3]:
    raise SystemExit('Review the upstream pin for this target kernel before building')
if hashlib.sha256(source.read_bytes()).hexdigest() != pin['t2gmux_sha256']:
    raise SystemExit('GMUX source differs from the reviewed pin')
PY
mkdir -p -- "$output/source"
cp -- "$source_tree/modules/t2gmux/t2gmux.c" "$output/source/"
printf 'obj-m += t2gmux.o\n' > "$output/source/Makefile"
make -C "$headers" M="$output/source" -j"${JOBS:-2}" modules 2>&1 | tee "$output/build.log"
objcopy --strip-debug "$output/source/t2gmux.ko" "$output/t2gmux.ko"
[[ $(modinfo -F vermagic "$output/t2gmux.ko") == "$release "* ]] || { echo 'Built module release mismatch' >&2; exit 1; }
python3 - "$output" "$release" "$repo/kernel/hybrid-upstream.json" <<'PY'
import hashlib, json, pathlib, subprocess, sys
out = pathlib.Path(sys.argv[1])
module = out / 't2gmux.ko'
manifest = dict(kernel=sys.argv[2], upstream=json.loads(pathlib.Path(sys.argv[3]).read_text()),
                module_sha256=hashlib.sha256(module.read_bytes()).hexdigest(),
                module_srcversion=subprocess.check_output(['modinfo', '-F', 'srcversion', str(module)], text=True).strip())
(out / 'module-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
printf 'Built %s/t2gmux.ko; nothing installed. See docs/HYBRID.md.\n' "$output"
