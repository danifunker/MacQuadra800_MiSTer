#!/usr/bin/env bash
# Rebuild the instrumented simulator from commit 0b2d265 and repeat the run.
# Usage: bash rerun.sh <new_scratch_dir>      (takes ~2 h; launch it durable:
#   systemd-run --user --unit=fpu-subtest-rerun --collect bash /abs/rerun.sh /abs/newdir)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/home/alans/mister/MacQuadra800_MiSTer
OUT="$1"; [ -e "$OUT" ] && { echo "refusing: $OUT exists" >&2; exit 2; }
mkdir -p "$OUT/tree"
git -C "$REPO" archive 0b2d265 rtl verilator releases/quadra800.rom docs/tools/make-fastboot-rom.sh \
    scripts/fixtures/speedometer_timing_observer | tar -x -C "$OUT/tree"
( cd "$OUT/tree" && sha256sum -c "$HERE/rtl_0b2d265_sha256.txt" --quiet )
grep -q P250 "$OUT/tree/rtl/ap68040/rtl/ap040_core.v" && { echo "unexpected P250 in core" >&2; exit 3; }
cp "$HERE/tree/verilator/fpu_window_monitor.h" "$OUT/tree/verilator/"
( cd "$OUT/tree/verilator" && patch -p0 --no-backup-if-mismatch Makefile < "$HERE/Makefile.diff" \
  && patch -p0 --no-backup-if-mismatch sim_main.cpp < "$HERE/sim_main.cpp.diff" )
# verilator/sim/mac is a gitignored mirror of Main_MiSTer support/mac; reuse ours
[ -d "$OUT/tree/verilator/sim/mac" ] || cp -a "$HERE/tree/verilator/sim/mac" "$OUT/tree/verilator/sim/"
make -C "$OUT/tree/verilator" fastboot
make -C "$OUT/tree/verilator" -j8 V=/home/alans/verilator5/bin/verilator
cp "$HERE/control.txt" "$HERE/HEAD_COMMIT.txt" "$HERE/run_fullguest.sh" "$HERE/analyze.py" "$HERE/timeline_markers.py" "$OUT/"
bash "$OUT/run_fullguest.sh" fpu_run
cd "$OUT"
python3 timeline_markers.py fpu_run/fwm.txt > markers.txt
python3 analyze.py fpu_run/fwm.txt --window "Whetstone:95:139" \
  --window "MatrixMultiply (3 timed runs):156:655" --window "FastFourier (5 timed runs):673:1056" \
  --json windows.json --md windows.md
echo "check markers.txt: the segment numbers above hold only if the run is cycle-identical"
