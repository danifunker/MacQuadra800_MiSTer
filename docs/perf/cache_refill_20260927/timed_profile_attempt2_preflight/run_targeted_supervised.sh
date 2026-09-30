#!/usr/bin/env bash
# Durable outer wrapper for the frozen targeted baseline runner.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
meta="$here/targeted_baseline_supervised.meta"
runner="$here/run_targeted_baseline.sh"
run_dir="$here/baseline_sim/verilator"
expected_disk_sha256=80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888

test -f "$here/source_manifest.sha256" || exit 66
test -x "$run_dir/obj_dir/Vemu" || exit 66
for output in fpu_timed_profile.tsv fpu_timed_observer.log fpu_timed_run.log fpu_refill_timed_run.tsv; do
    test ! -e "$run_dir/$output" || exit 73
done
test ! -e "$here/build/prelaunch_manifest_check.log" || exit 73

if [[ -e "$meta" ]]; then
    printf 'Refusing to overwrite existing run metadata: %s\n' "$meta" >&2
    exit 73
fi

sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

started_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
disk_sha256="$(sha256_of "$run_dir/run.hda")"
binary_sha256="$(sha256_of "$run_dir/obj_dir/Vemu")"
runner_sha256="$(sha256_of "$runner")"
manifest_sha256="$(sha256_of "$here/source_manifest.sha256")"
control_sha256="$(sha256_of "$run_dir/fpu_control_full.txt")"

{
    printf 'run_id=targeted_baseline_%s\n' "${started_utc//[-:TZ]/}"
    printf 'wrapper_pid=%s\n' "$$"
    printf 'hostname=%s\n' "$(hostname)"
    printf 'started_utc=%s\n' "$started_utc"
    printf 'cwd=%s\n' "$run_dir"
    printf 'inner_runner=%s\n' "$runner"
    printf 'inner_runner_sha256=%s\n' "$runner_sha256"
    printf 'source_manifest_sha256=%s\n' "$manifest_sha256"
    printf 'binary_sha256=%s\n' "$binary_sha256"
    printf 'disk_sha256=%s\n' "$disk_sha256"
    printf 'control_sha256=%s\n' "$control_sha256"
    printf 'expected_disk_sha256=%s\n' "$expected_disk_sha256"
    printf 'exit_status=RUNNING\n'
} > "$meta"

finish() {
    local status=$?
    trap - EXIT
    printf 'exit_status=%s\nfinished_utc=%s\n' "$status" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$meta"
    exit "$status"
}
trap finish EXIT

if [[ "$disk_sha256" != "$expected_disk_sha256" ]]; then
    printf 'Disk SHA256 mismatch; refusing to launch.\n' >&2
    exit 65
fi

cd "$here"
status=0
./run_targeted_baseline.sh || status=$?
exit "$status"
