#!/usr/bin/env python3
"""Patch only the isolated baseline simulator copy for timed FPU profiling."""
from pathlib import Path
import hashlib
import shutil

root = Path(__file__).parent / "baseline_sim" / "verilator"
source = root / "sim_main.cpp"
data = source.read_text()
expected = "015e3505d834d3368494acc4810849989af9602d9775d8217880b10325893c7a"
if hashlib.sha256(data.encode()).hexdigest() != expected:
    raise SystemExit("isolated sim_main source identity differs from frozen baseline")

def replace_one(old: str, new: str) -> None:
    global data
    if data.count(old) != 1:
        raise SystemExit(f"expected one anchor: {old[:80]!r}; found {data.count(old)}")
    data = data.replace(old, new, 1)

replace_one(
    '#include "../scripts/fixtures/speedometer_timing_observer/adapter.inc"\n',
    '''#include "../scripts/fixtures/speedometer_timing_observer/adapter.inc"
#include "../scripts/fixtures/speedometer_timing_observer/fpu_timed_profile.h"
static std::string fpu_timed_path;
static std::unique_ptr<FpuTimedProfile> fpu_timed_profile;
static bool fpu_timed_finished=false;
static void fpu_timed_finish() {
    if(!fpu_timed_profile || fpu_timed_finished)return;
    if(speedometer_observer) {
        speedometer_observer->finish(main_time/2);
        speedometer_observer->set_fpu_sink({});
    }
    if(!fpu_timed_profile->dump())
        fprintf(stderr,"[FPU-TIMED] cannot write %s\\n",fpu_timed_path.c_str());
    else printf("[FPU-TIMED] wrote %s\\n",fpu_timed_path.c_str());
    fpu_timed_finished=true;
}
static void fpu_timed_step(bool dispatch) {
    if(!fpu_timed_profile || fpu_timed_finished)return;
    WindowSample s;
    s.core_state=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__state;
    s.cache_state=SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__cst;
    s.fpu_state=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__g_fpu__DOT__fpu__DOT__fst;
    s.fpu_op=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__g_fpu__DOT__fpu__DOT__r_op;
    s.fpu_bg=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_bg;
    s.fpu_done=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_done;
    s.dispatch=dispatch;
    s.fill_acked=SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__fill_acked;
    fpu_timed_profile->sample(s);
}
''')
replace_one('if (action == CpuProfileGate::Stop) { bracket_dump(); return; }',
            'if (action == CpuProfileGate::Stop) { fpu_timed_finish(); bracket_dump(); return; }')
replace_one('speedometer_after_eval(dispatched);\n\t\t\t\tbracket_step(dispatched);',
            'speedometer_after_eval(dispatched);\n\t\t\t\tbracket_step(dispatched);\n\t\t\t\tfpu_timed_step(dispatched);')
replace_one('} else if (!strcmp(argv[i], "--speedometer-limit") && i + 1 < argc) {',
            '} else if (!strcmp(argv[i], "--fpu-timed-profile") && i + 1 < argc) {\n'
            '            fpu_timed_path = argv[++i];\n'
            '        } else if (!strcmp(argv[i], "--speedometer-limit") && i + 1 < argc) {')
replace_one('    if (!speedometer_path.empty()) {\n',
            '    if (!fpu_timed_path.empty() && speedometer_path.empty()) {\n'
            '        fprintf(stderr,"--fpu-timed-profile requires --speedometer-observe\\n"); return 1;\n'
            '    }\n'
            '    if (!speedometer_path.empty()) {\n')
replace_one('        speedometer_observer.reset(new speedometer::Observer(speedometer_file, speedometer_limit));\n',
            '        speedometer_observer.reset(new speedometer::Observer(speedometer_file, speedometer_limit));\n'
            '        if(!fpu_timed_path.empty()) {\n'
            '            fpu_timed_profile.reset(new FpuTimedProfile(fpu_timed_path));\n'
            '            speedometer_observer->set_fpu_sink([](const speedometer::FpuEvent& e) {\n'
            '                fpu_timed_profile->event(e);\n'
            '            });\n'
            '        }\n')
replace_one('if (speedometer_observer) speedometer_observer->summary();',
            'fpu_timed_finish();\n\tif (speedometer_observer) speedometer_observer->summary();')
source.write_text(data)

makefile = root / "Makefile"
data = makefile.read_text()
anchor = "../scripts/fixtures/speedometer_timing_observer/speedometer_observer.h"
if data.count(anchor) != 1:
    raise SystemExit("unexpected Makefile header anchor")
data = data.replace(anchor, anchor + " ../scripts/fixtures/speedometer_timing_observer/fpu_timed_profile.h ../scripts/fixtures/speedometer_timing_observer/window_counters.h")
makefile.write_text(data)
observer_dir = root.parent / "scripts" / "fixtures" / "speedometer_timing_observer"
for header in ("speedometer_observer.h", "window_counters.h", "fpu_timed_profile.h"):
    shutil.copy2(Path(__file__).parent / header, observer_dir / header)
print("patched isolated simulator", source)
