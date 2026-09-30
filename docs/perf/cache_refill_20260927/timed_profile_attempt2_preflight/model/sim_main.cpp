#include <map>
// wombat33 — Verilator simulation main
//
// Same framework as the other cores' verilator setups (ImGui + SDL2,
// sim_video/sim_clock/sim_input helpers, FST tracing): a control window
// with run/pause/step, the core's option bits, and the emulated screen.
// Today it drives the MiSTer template pattern core in sim.v; the AP68040
// machine drops into the same shell as bring-up proceeds.

#include <verilated.h>
#include "Vemu.h"
#include "Vemu__Syms.h"

#include "imgui.h"
#include <stdio.h>
#include <SDL.h>
#include <SDL_opengl.h>

#define VERILATOR_MAJOR_VERSION (VERILATOR_VERSION_INTEGER / 1000000)
#if VERILATOR_MAJOR_VERSION >= 5
#define VERTOPINTERN top->rootp
#else
#define VERTOPINTERN top
#endif

#include "sim_console.h"
#include "sim_video.h"
#include "sim_input.h"
#include "sim_clock.h"
#include "sim_audio.h"
#include "sim_blkdevice.h"
#include "implot.h"
#include "m68k_dasm.h"
#include "sim_control.h"
#include "cpu_dispatch_observer.h"
#include <csignal>

// sim.v keeps its own module class (the public arrays force it), so its
// internals live under rootp->emu rather than flattened into root.
#define SIMEMU (top->rootp->emu)

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "sim/stb_image_write.h"

#include <string>
#include <sstream>
#include <vector>
#include <algorithm>

// Simulation control
// ------------------
int  initialReset = 48;
bool run_enable = 1;
int  batchSize = 500000;
bool single_step = 0;
bool multi_step = 0;
int  multi_step_amount = 1024;

// Core options (mirrors the CONF_STR options in MacQuadra800.sv)
int opt_tvmode = 0;      // 0 NTSC, 1 PAL
int opt_noise = 0;       // 0 white, 1 red, 2 green, 3 blue

// Headless / scripted runs
bool headless = false;
bool screenshot_mode = false;
std::vector<int> screenshot_frames;
int  stop_at_frame = -1;
vluint64_t max_cycles = 0;      // --max-cycles N: stop after N clk edges (0 = off)
vluint64_t trace_after = 0;     // --trace-after N: suppress the cpu trace before cycle N
uint32_t stop_pc_lo = 1, stop_pc_hi = 0;   // --stop-at-pc lo,hi: exit when pc_i enters range
bool pc_was_in_stop = false;               // edge detector for the stop range

// CPU instruction trace (MacLC cpu_trace pattern, adapted to AP68040's
// pc_i register: one entry per instruction dispatch, extension words read
// straight from the sim memory arrays)
bool cpu_trace_disabled = false;      // --no-cpu-trace
bool trace_on_ncr = false;            // --trace-on-ncr: start when the NCR reg trace arms
long trace_max = 0;                   // --trace-max N: stop tracing after N instructions
#define NCR_REGTRACE (SIMEMU->__PVT__machine__DOT__iosb__DOT__scsi__DOT__dbg_regtrace)
bool gui_instr_log = false;           // stream instructions into the Debug log
bool gui_trace_file = true;           // trace file toggle (GUI defaults off)
bool showDebugLog = true;
FILE* cpu_trace_file = nullptr;
const char* cpu_trace_filename = "cpu_trace.log";
long cpu_trace_count = 0;
uint32_t cpu_trace_last_pc = 0xFFFFFFFF;

// Cheap long-run observability: heartbeat line + a pc histogram (one
// bucket per 256 bytes over the whole 4 GB, sampled every clock).
vluint64_t heartbeat_every = 10000000;
vluint64_t next_heartbeat = 10000000;
bool pc_hist_enable = false;    // --hist: per-cycle pc histogram (slows the sim)
// --prof: per-state cycle histogram of the AP68040 sequencer, sampled every
// clk_sys, plus how many S_MRD/S_MWR cycles were spent waiting for a queue
// fetch to release the shared memory port.  Printed with every heartbeat.
bool cpu_prof_enable = false;
static uint64_t prof_state[256];
static uint64_t prof_total = 0, prof_portwait = 0, prof_dispatch = 0;
static uint8_t  prof_prev_state = 0;
// S_MRD/S_MWR cycles split by where the access is (cache FSM state) and
// what it targets (address region), plus acceptance-cycle cache hits
static uint64_t prof_mrd_cst[8], prof_mwr_cst[8];
static uint64_t prof_mrd_region[5], prof_mwr_region[5];   // ram, rom, io, vram, other
static int prof_region(uint32_t a) {
	return (a < 0x10000000u) ? 0 : ((a >> 28) == 4) ? 1 : ((a >> 28) == 5) ? 2 :
	       ((a >> 21) == 0x7C8) ? 3 : 4;                          // $F9000000-$F91FFFFF
}
static uint64_t prof_fast_hit_i = 0, prof_fast_hit_d = 0;
// S_FETCH split: cycles with a queue fetch outstanding (the opcode is on its
// way) versus without one (re-arming, or a redirect not yet issued), and the
// completed transactions per region so the S_MRD/S_MWR cycles read as an
// average latency per access.
static uint64_t prof_fetch_pend = 0, prof_fetch_nopend = 0;
static uint64_t prof_dack_rd[5], prof_dack_wr[5], prof_iack = 0;
static const char* prof_cst_name[8] = {"IDLE","LOOK","FERR","WINV","FILL","TAGW","PASS","SWEEP"};
static const char* prof_region_name[5] = {"ram","rom","io","vram","other"};
static void cpu_prof_print() {
	int idx[256];
	for (int i = 0; i < 256; i++) idx[i] = i;
	std::sort(idx, idx + 256, [](int a, int b) { return prof_state[a] > prof_state[b]; });
	printf("[PROF] %llu cycles, %llu dispatches (%.2f clk/dispatch), port-wait %llu (%.1f%%)\n",
	       (unsigned long long)prof_total, (unsigned long long)prof_dispatch,
	       prof_dispatch ? (double)prof_total / prof_dispatch : 0.0,
	       (unsigned long long)prof_portwait,
	       prof_total ? 100.0 * prof_portwait / prof_total : 0.0);
	for (int i = 0; i < 14 && prof_state[idx[i]]; i++)
		printf("[PROF]   state %3d: %llu (%.1f%%)\n", idx[i],
		       (unsigned long long)prof_state[idx[i]],
		       100.0 * prof_state[idx[i]] / prof_total);
	printf("[PROF]   S_MRD by cache state:");
	for (int i = 0; i < 8; i++) if (prof_mrd_cst[i]) printf(" %s=%llu", prof_cst_name[i], (unsigned long long)prof_mrd_cst[i]);
	printf("\n[PROF]   S_MRD by region:");
	for (int i = 0; i < 5; i++) if (prof_mrd_region[i]) printf(" %s=%llu", prof_region_name[i], (unsigned long long)prof_mrd_region[i]);
	printf("\n[PROF]   S_MWR by cache state:");
	for (int i = 0; i < 8; i++) if (prof_mwr_cst[i]) printf(" %s=%llu", prof_cst_name[i], (unsigned long long)prof_mwr_cst[i]);
	printf("\n[PROF]   S_MWR by region:");
	for (int i = 0; i < 5; i++) if (prof_mwr_region[i]) printf(" %s=%llu", prof_region_name[i], (unsigned long long)prof_mwr_region[i]);
	printf("\n[PROF]   acceptance-cycle hits: instr %llu, data %llu\n",
	       (unsigned long long)prof_fast_hit_i, (unsigned long long)prof_fast_hit_d);
	printf("[PROF]   S_FETCH: fetch outstanding %llu, none outstanding %llu; instruction acks %llu\n",
	       (unsigned long long)prof_fetch_pend, (unsigned long long)prof_fetch_nopend,
	       (unsigned long long)prof_iack);
	printf("[PROF]   data reads by region (acks/avg S_MRD clk):");
	for (int i = 0; i < 5; i++) if (prof_dack_rd[i])
		printf(" %s=%llu/%.1f", prof_region_name[i], (unsigned long long)prof_dack_rd[i],
		       (double)prof_mrd_region[i] / prof_dack_rd[i]);
	printf("\n[PROF]   data writes by region (acks/avg S_MWR clk):");
	for (int i = 0; i < 5; i++) if (prof_dack_wr[i])
		printf(" %s=%llu/%.1f", prof_region_name[i], (unsigned long long)prof_dack_wr[i],
		       (double)prof_mwr_region[i] / prof_dack_wr[i]);
	printf("\n");
}
static uint32_t pc_hist[1 << 24];
static uint32_t pc_hist_pc(int i) { return (uint32_t)i << 8; }

static uint16_t sim_read_word(uint32_t addr);
static void cpu_trace_step();
static void machine_events();

// Verilog module
// --------------
Vemu* top = NULL;
vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

SimClock clk_sys(1);
SimAudio audio(33000000, false);
std::string scsi_disk_file;      // --disk <path> mounts on SCSI ID 0
std::string scsi_cd_file;        // --cd <path> mounts a flat 2048-byte disc on the CD-ROM (SCSI ID 3)

DebugConsole console;
SimBlockDevice blockdevice(console);
const char* windowTitle = "wombat33 sim";
const char* windowTitle_Control = "Simulation control";
const char* windowTitle_Video = "VGA output";

// Video: template pattern is 640x480-ish; the window autosizes to the
// measured extents anyway.
SimVideo video(800, 600, 0);
float vga_scale = 1.0f;
SimInput input(12, console);

static std::string control_file;
static SimControl sim_control;
static bool control_shot_pending = false;
static CpuDispatchObserver dispatch_observer;
static bool dispatched = false;

#include "../scripts/fixtures/speedometer_timing_observer/adapter.inc"
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
        fprintf(stderr,"[FPU-TIMED] cannot write %s\n",fpu_timed_path.c_str());
    else printf("[FPU-TIMED] wrote %s\n",fpu_timed_path.c_str());
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
#include "sim_ram_snapshot.h"
#include "sim_refill_profile.h"

// Simulation-only exact-workload profiler. SIGUSR1 resets/starts the
// bracket; SIGUSR2 stops it and writes the report.
// Dispatch means an actual opcode load, before decode/operand execution.
// Faulting opcodes are included; clocks_per_dispatch is not retirement CPI.
static std::string bracket_file;
static volatile sig_atomic_t bracket_start_req = 0, bracket_stop_req = 0;
static CpuProfileGate bracket_gate;
static bool bracket_prev_valid = false;
static uint8_t bracket_prev_state = 0;
static uint64_t bracket_dispatches = 0;
static uint64_t bracket_cycles, bracket_state_cycles[256], bracket_state_entries[256];
static uint64_t bracket_transitions[256][256], bracket_opcodes[65536];
// cache maintenance (CINV/CPUSH, F4xx): dispatch PC and the return address on
// the stack, to find who flushes (2026-09-26)
static std::map<uint64_t, uint64_t> bracket_f4_sites, bracket_f4_calls;
static uint64_t bracket_cache_states[8], bracket_rd_accept, bracket_look_hit, bracket_ipred_hit;

static uint64_t bracket_ic_enabled, bracket_dc_enabled, bracket_mmu_enabled;
// Memory-path attribution: where the core's memory states wait.
static uint64_t bracket_mrd_cst[8], bracket_mwr_cst[8], bracket_mrd_sbpend, bracket_mwr_sbpend;
static uint64_t bracket_fill_d, bracket_fill_i, bracket_sb_full, bracket_read_behind_store;
static uint64_t bracket_pass_write, bracket_pass_read, bracket_sb_pushes;
static uint8_t bracket_prev_cst = 0;
static SimRefillProfile bracket_refill;
static void bracket_start_signal(int) { bracket_start_req = 1; }
static void bracket_stop_signal(int) { bracket_stop_req = 1; }

static void bracket_reset() {
	bracket_dispatches = 0;
	bracket_cycles = bracket_rd_accept = bracket_look_hit = bracket_ipred_hit = 0;
	bracket_ic_enabled = bracket_dc_enabled = bracket_mmu_enabled = 0;
	memset(bracket_state_cycles, 0, sizeof(bracket_state_cycles));
	memset(bracket_state_entries, 0, sizeof(bracket_state_entries));
	memset(bracket_transitions, 0, sizeof(bracket_transitions));
	memset(bracket_opcodes, 0, sizeof(bracket_opcodes));
	bracket_f4_sites.clear(); bracket_f4_calls.clear();
	memset(bracket_cache_states, 0, sizeof(bracket_cache_states));
	memset(bracket_mrd_cst, 0, sizeof(bracket_mrd_cst)); memset(bracket_mwr_cst, 0, sizeof(bracket_mwr_cst));
	bracket_mrd_sbpend = bracket_mwr_sbpend = bracket_fill_d = bracket_fill_i = bracket_sb_full = 0;
	bracket_read_behind_store = bracket_pass_write = bracket_pass_read = bracket_sb_pushes = 0;
	bracket_prev_valid = false;
	bracket_prev_cst = 0xff;
	bracket_refill.reset();
}

static void bracket_dump() {
	if (bracket_file.empty()) return;
	bracket_refill.stop();
	FILE* f = fopen(bracket_file.c_str(), "w");
	if (!f) { fprintf(stderr, "[CPU-PROFILE] cannot write %s\n", bracket_file.c_str()); return; }
	uint64_t dispatches = bracket_dispatches;
	// End configuration is explicitly labelled; enabled-cycle counts describe
	// the complete bracket even if guest software changes CACR/TC within it.
	fprintf(f, "CONFIG_END\tpc\tcacr\ttc\n");
	fprintf(f, "CONFIG_END\t%08X\t%08X\t%08X\n",
	        SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i,
	        SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__cacr,
	        SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__tc);
	fprintf(f, "ENABLED_CYCLES\tic\tdc\tmmu\n");
	fprintf(f, "ENABLED_CYCLES\t%llu\t%llu\t%llu\n",
	        (unsigned long long)bracket_ic_enabled,
	        (unsigned long long)bracket_dc_enabled,
	        (unsigned long long)bracket_mmu_enabled);
	double cpd = dispatches ? (double)bracket_cycles / dispatches : 0.0;
	fprintf(f, "SUMMARY\tcycles\tdispatches\tclocks_per_dispatch\trd_accept_samples\tlook_hit_cycles\tipred_hit_cycles\n");
	fprintf(f, "SUMMARY\t%llu\t%llu\t%.6f\t%llu\t%llu\t%llu\n",
	        (unsigned long long)bracket_cycles, (unsigned long long)dispatches, cpd,
	        (unsigned long long)bracket_rd_accept, (unsigned long long)bracket_look_hit,
	        (unsigned long long)bracket_ipred_hit);
	fprintf(f, "STATE\tid\tcycles\tentries\tpercent\n");
	for (int i=0; i<256; i++) if (bracket_state_cycles[i])
		fprintf(f, "STATE\t%d\t%llu\t%llu\t%.6f\n", i,
		        (unsigned long long)bracket_state_cycles[i],
		        (unsigned long long)bracket_state_entries[i],
		        bracket_cycles ? 100.0*bracket_state_cycles[i]/bracket_cycles : 0.0);
	fprintf(f, "MEM\tname\tvalue\n");
	for (int i=0;i<8;i++) if (bracket_mrd_cst[i]) fprintf(f, "MEM\tmrd_cycles_cst%d\t%llu\n", i, (unsigned long long)bracket_mrd_cst[i]);
	for (int i=0;i<8;i++) if (bracket_mwr_cst[i]) fprintf(f, "MEM\tmwr_cycles_cst%d\t%llu\n", i, (unsigned long long)bracket_mwr_cst[i]);
	fprintf(f, "MEM\tmrd_cycles_sb_pending\t%llu\n", (unsigned long long)bracket_mrd_sbpend);
	fprintf(f, "MEM\tmwr_cycles_sb_pending\t%llu\n", (unsigned long long)bracket_mwr_sbpend);
	fprintf(f, "MEM\tdata_tagwrite_entries\t%llu\n", (unsigned long long)bracket_fill_d);
	fprintf(f, "MEM\tinstr_tagwrite_entries\t%llu\n", (unsigned long long)bracket_fill_i);
	fprintf(f, "MEM\tsb_push_signal_samples\t%llu\n", (unsigned long long)bracket_sb_pushes);
	fprintf(f, "MEM\tsb_full_request_samples\t%llu\n", (unsigned long long)bracket_sb_full);
	fprintf(f, "MEM\tread_with_store_pending_samples\t%llu\n", (unsigned long long)bracket_read_behind_store);
	fprintf(f, "MEM\tpass_cycles_write\t%llu\n", (unsigned long long)bracket_pass_write);
	fprintf(f, "MEM\tpass_cycles_read\t%llu\n", (unsigned long long)bracket_pass_read);
	// Post-eval refill register samples. The issued/acked columns describe
	// cache state at the edge; they are not memory bus transaction counts.
	fprintf(f, "REFILL_META\tclock_sample\tpost_eval_rising_edge\n");
	fprintf(f, "REFILL_META\tduration\tC_FILL_through_C_TAGW_complete_bracket_spans_only\n");
	fprintf(f, "REFILL_META\tmrd_overlap\tcore_state_9_and_C_FILL_same_sample\n");
	fprintf(f, "REFILL_META\tstates\tissued_is_registered_state_local_match_is_combinational_setup_is_neither\n");
	fprintf(f, "REFILL_PARTIAL\tstart\t%llu\n", (unsigned long long)bracket_refill.partial_at_start);
	fprintf(f, "REFILL_PARTIAL\tend\t%llu\n", (unsigned long long)bracket_refill.partial_at_end);
	fprintf(f, "REFILL_PARTIAL\taborted\t%llu\n", (unsigned long long)bracket_refill.aborted);
	fprintf(f, "REFILL_REGION\tbank\tregion\tfill_entries\tfill_samples\ttagwrite_samples\tissued_state_samples\tlocal_match_samples\tsetup_state_samples\tmrd_overlap_samples\tcompleted\n");
	for (int bank = 0; bank < 2; bank++) for (int reg = 0; reg < 3; reg++) {
		uint64_t fill = 0;
		for (int beat = 0; beat < 4; beat++) for (int issued = 0; issued < 2; issued++)
			for (int acked = 0; acked < 2; acked++)
				fill += bracket_refill.fill_samples[bank][reg][beat][issued][acked];
		if (fill || bracket_refill.tagwrite_samples[bank][reg])
			fprintf(f, "REFILL_REGION\t%s\t%s\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\n",
			        bank ? "instruction" : "data", reg == 0 ? "ram" : reg == 1 ? "rom" : "other",
			        (unsigned long long)bracket_refill.fill_entries[bank][reg],
			        (unsigned long long)fill,
			        (unsigned long long)bracket_refill.tagwrite_samples[bank][reg],
			        (unsigned long long)bracket_refill.issued_state_samples[bank][reg],
			        (unsigned long long)bracket_refill.local_match_samples[bank][reg],
			        (unsigned long long)bracket_refill.setup_state_samples[bank][reg],
			        (unsigned long long)bracket_refill.mrd_overlap_samples[bank][reg],
			        (unsigned long long)bracket_refill.completed[bank][reg]);
	}
	fprintf(f, "REFILL_SAMPLE\tbank\tregion\tfill_cnt\tr_issued\tfill_acked\tclocks\n");
	for (int bank = 0; bank < 2; bank++) for (int reg = 0; reg < 3; reg++)
		for (int beat = 0; beat < 4; beat++) for (int issued = 0; issued < 2; issued++)
			for (int acked = 0; acked < 2; acked++) {
				uint64_t clocks = bracket_refill.fill_samples[bank][reg][beat][issued][acked];
				if (clocks) fprintf(f, "REFILL_SAMPLE\t%s\t%s\t%d\t%d\t%d\t%llu\n",
				                    bank ? "instruction" : "data", reg == 0 ? "ram" : reg == 1 ? "rom" : "other",
				                    beat, issued, acked, (unsigned long long)clocks);
			}
	fprintf(f, "REFILL_DURATION\tbank\tregion\tclocks\tcomplete_fills\n");
	for (const auto &kv : bracket_refill.duration_hist) {
		const unsigned bank = (kv.first >> 2) & 1, reg = kv.first & 3;
		fprintf(f, "REFILL_DURATION\t%s\t%s\t%llu\t%llu\n",
		        bank ? "instruction" : "data", reg == 0 ? "ram" : reg == 1 ? "rom" : "other",
		        (unsigned long long)(kv.first >> 3), (unsigned long long)kv.second);
	}
	fprintf(f, "CACHE_STATE\tid\tcycles\tpercent\n");
	for (int i=0; i<8; i++) if (bracket_cache_states[i])
		fprintf(f, "CACHE_STATE\t%d\t%llu\t%.6f\n", i,
		        (unsigned long long)bracket_cache_states[i],
		        bracket_cycles ? 100.0*bracket_cache_states[i]/bracket_cycles : 0.0);
	fprintf(f, "TRANSITION\tfrom\tto\tcount\n");
	for (int a=0; a<256; a++) for (int b=0; b<256; b++)
		if (bracket_transitions[a][b])
			fprintf(f, "TRANSITION\t%d\t%d\t%llu\n", a, b,
			        (unsigned long long)bracket_transitions[a][b]);
	std::vector<int> ops;
	for (int i=0; i<65536; i++) if (bracket_opcodes[i]) ops.push_back(i);
	std::sort(ops.begin(), ops.end(), [](int a,int b) { return bracket_opcodes[a] > bracket_opcodes[b]; });
	for (auto &kv : bracket_f4_sites)
		fprintf(f, "F4SITE\t%04X\t%08X\t%llu\n", (unsigned)(kv.first >> 32), (uint32_t)kv.first,
		        (unsigned long long)kv.second);
	for (auto &kv : bracket_f4_calls)
		if (kv.second >= 100)
			fprintf(f, "F4CALL\t%08X\t%08X\t%llu\n", (uint32_t)(kv.first >> 32), (uint32_t)kv.first,
			        (unsigned long long)kv.second);
	fprintf(f, "OPCODE\topcode\tdispatches\tpercent\n");
	for (int op: ops)
		fprintf(f, "OPCODE\t%04X\t%llu\t%.6f\n", op,
		        (unsigned long long)bracket_opcodes[op],
		        dispatches ? 100.0*bracket_opcodes[op]/dispatches : 0.0);
	fclose(f);
	printf("[CPU-PROFILE] wrote %s: %llu cycles, %llu opcode dispatches, %.3f clocks/dispatch\n",
	       bracket_file.c_str(), (unsigned long long)bracket_cycles,
	       (unsigned long long)dispatches, cpd);
	fflush(stdout);
}

static void bracket_step(bool dispatch) {
	const bool start = bracket_start_req != 0, stop = bracket_stop_req != 0;
	if (start) bracket_start_req = 0;
	if (start || stop) bracket_stop_req = 0;
	const auto action = bracket_gate.sample(start, stop);
	if (action == CpuProfileGate::Start) {
		bracket_reset();
		printf("[CPU-PROFILE] started at simulator cycle %llu\n", (unsigned long long)main_time);
		fflush(stdout);
	}
	if (action == CpuProfileGate::Stop) { fpu_timed_finish(); bracket_dump(); return; }
	if (action == CpuProfileGate::Skip) return;
	uint8_t state=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__state;
	uint16_t ir=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__ir;
	uint8_t cst=SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__cst;
	bracket_cycles++; bracket_state_cycles[state]++; bracket_cache_states[cst&7]++;
	{
		const uint8_t sbc = SIMEMU->__PVT__machine__DOT__cpu__DOT__store_buffer__DOT__count;
		const bool sbreq = SIMEMU->__PVT__machine__DOT__cpu__DOT__store_buffer__DOT__buffer_req;
		const bool busreq = SIMEMU->__PVT__machine__DOT__cpu__DOT__cpu_bus_req;
		const bool buswr = SIMEMU->__PVT__machine__DOT__cpu__DOT__cpu_bus_write;
		const bool rbank = SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__r_bank;
		bracket_refill.sample(cst & 7, rbank,
			SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__r_addr,
			SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__fill_cnt,
			SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__r_issued,
			SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__fill_acked,
			SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__fill_line_match,
			state == 9);
		if (state == 9) { bracket_mrd_cst[cst&7]++; if (sbc) bracket_mrd_sbpend++; }
		if (state == 10) { bracket_mwr_cst[cst&7]++; if (sbc) bracket_mwr_sbpend++; }
		if ((cst&7) == 5 && bracket_prev_cst != 5) { if (rbank) bracket_fill_i++; else bracket_fill_d++; }
		if (sbreq && !SIMEMU->__PVT__machine__DOT__cpu__DOT__store_buffer__DOT__push &&
            !SIMEMU->__PVT__machine__DOT__cpu__DOT__store_buffer__DOT__accept_ack) bracket_sb_full++;
		if (busreq && !buswr && sbc) bracket_read_behind_store++;
		if ((cst&7) == 6) { if (buswr) bracket_pass_write++; else bracket_pass_read++; }
		if (SIMEMU->__PVT__machine__DOT__cpu__DOT__store_buffer__DOT__push) bracket_sb_pushes++;
		bracket_prev_cst = cst&7;
	}
	if (SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__rd_accept) bracket_rd_accept++;
	const uint32_t cacr = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__cacr;
	bracket_ic_enabled += (cacr >> 15) & 1;
	bracket_dc_enabled += (cacr >> 31) & 1;
	bracket_mmu_enabled += (SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__tc >> 15) & 1;
	if (SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__look_hit) bracket_look_hit++;
	if (SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__ipred_hit) bracket_ipred_hit++;
	// The continuously sampled opcode-load toggle handles bypassed decode,
	// consecutive same-PC/state dispatches, and clock-enable stalls alike.
	if (dispatch) {
		bracket_dispatches++;
		bracket_opcodes[ir]++;
		if ((ir & 0xFF00) == 0xF400) {
			const uint32_t pc = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i;
			const uint32_t a7 = VERTOPINTERN->debug_a7;
			const uint32_t ret = ((a7 >> 2) < sizeof(SIMEMU->ram) / sizeof(SIMEMU->ram[0])) ? SIMEMU->ram[a7 >> 2] : 0;
			bracket_f4_sites[((uint64_t)ir << 32) | pc]++;
			bracket_f4_calls[((uint64_t)pc << 32) | ret]++;
		}
	}
	if (!bracket_prev_valid || state != bracket_prev_state) {
		bracket_state_entries[state]++;
		if (bracket_prev_valid) bracket_transitions[bracket_prev_state][state]++;
		bracket_prev_state=state; bracket_prev_valid=true;
	}
}

// ---- ADB mouse from clicks on the VGA image -------------------------------

// Local control never opens a stream or emits guest input unless --control
// is supplied. Reuse SimInput's normal PS/2-to-ADB queue and timing contract.
static void control_before_eval() {
	if (!sim_control.enabled()) return;
	SimControlCommand command{};
	if (sim_control.step(VERTOPINTERN->reset || control_shot_pending,
	                     input.keyEvents.empty() && input.keyEventTimer == 0, command)) {
		switch (command.kind) {
		case SimControlCommand::Down:
		case SimControlCommand::Up:
			input.keyEvents.emplace(static_cast<char>(command.value),
				command.kind == SimControlCommand::Down, command.extended,
				static_cast<unsigned>(command.value));
			printf("[SIM-CONTROL] %s %02llX%s cycle=%llu\n",
				command.kind == SimControlCommand::Down ? "down" : "up",
				(unsigned long long)command.value, command.extended ? " ext" : "",
				(unsigned long long)main_time);
			break;
		case SimControlCommand::Wait:
			printf("[SIM-CONTROL] wait %llu rising edges cycle=%llu\n",
				(unsigned long long)command.value, (unsigned long long)main_time);
			break;
		case SimControlCommand::Shot:
			control_shot_pending = true; // block following commands until frame capture
			break;
        case SimControlCommand::RamDump: {
            char path[96];
            snprintf(path, sizeof(path), "ram_snapshot_%llu.bin", (unsigned long long)main_time);
            FILE* snapshot = fopen(path, "wb");
            bool ok = write_guest_ram(snapshot, SIMEMU->ram, size_t(command.value) << 20);
            if (snapshot && fclose(snapshot) != 0) ok = false;
            printf("[RAM-SNAPSHOT] %s %s bytes=%llu cycle=%llu pc=%08X tc=%08X urp=%08X srp=%08X\n",
                ok ? "wrote" : "FAILED", path, (unsigned long long)(command.value << 20),
                (unsigned long long)main_time,
                SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i,
                SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__tc,
                SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__urp,
                SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__srp);
            break;
        }
		case SimControlCommand::Quit:
			run_enable = false;
			Verilated::gotFinish(true);
			break;
		case SimControlCommand::ProfileStart:
		case SimControlCommand::ProfileStop:
			if (bracket_file.empty()) fprintf(stderr, "[SIM-CONTROL] profile requires --cpu-profile FILE\n");
			else if (command.kind == SimControlCommand::ProfileStart) bracket_start_req = 1;
			else bracket_stop_req = 1;
			break;
		}
		fflush(stdout);
	}
	static size_t last_rejected = 0;
	if (sim_control.rejected() != last_rejected) {
		fprintf(stderr, "[SIM-CONTROL] rejected malformed/overlong commands: %zu total\n", sim_control.rejected());
		last_rejected = sim_control.rejected();
	}
	static std::string last_error;
	if (sim_control.read_error() != last_error) {
		last_error = sim_control.read_error();
		fprintf(stderr, "[SIM-CONTROL] read error: %s\n", last_error.c_str());
	}
}
// ---- ADB mouse from clicks on the VGA image -------------------------------
// A click (or drag) on the VGA output picks a target pixel; each GUI frame
// one MiSTer-format ps2_mouse packet nudges the pointer toward it.  The ADB
// mouse is relative, so the loop is closed against the Mac's own idea of the
// pointer — the RawMouse low-memory global at $82C ({v,h} words) — which
// self-corrects for clamped or overwritten deltas.  Before the System is up
// nobody maintains RawMouse, so a target that makes no progress is dropped
// after a few dozen packets instead of being chased forever.
static bool     mouse_btn_down   = false;   // hovered-image button state
static bool     mouse_btn_sent   = false;   // last button state delivered
static bool     mouse_btn_dirty  = false;
static int      mouse_warp_x     = -1;      // target in Mac pixels (-1 = idle)
static int      mouse_warp_y     = -1;
static uint32_t mouse_strobe     = 0;       // ps2_mouse[24] toggle
static uint32_t mouse_last_raw   = 0xFFFFFFFF;
static int      mouse_stalled    = 0;

static void adb_mouse_update() {
	if (mouse_warp_x < 0 && !mouse_btn_dirty) return;

	int dx = 0, dy = 0;
	if (mouse_warp_x >= 0) {
		// RawMouse at $082C: bytes {v.hi v.lo h.hi h.lo} = one big-endian
		// RAM word, v in [31:16], h in [15:0]
		uint32_t raw = SIMEMU->ram[0x082C >> 2];
		int v = (int)(raw >> 16), h = (int)(raw & 0xFFFF);
		if (h > 2047 || v > 2047) {              // boot fill / no cursor yet
			mouse_warp_x = mouse_warp_y = -1;
		}
		else {
			dx = mouse_warp_x - h;
			dy = mouse_warp_y - v;
			if (dx == 0 && dy == 0) {
				mouse_warp_x = mouse_warp_y = -1;    // arrived
			}
			else if (raw == mouse_last_raw && ++mouse_stalled > 48) {
				mouse_warp_x = mouse_warp_y = -1;    // nobody is listening
				mouse_stalled = 0;
			}
			if (raw != mouse_last_raw) mouse_stalled = 0;
			mouse_last_raw = raw;
		}
	}
	if (mouse_warp_x < 0 && !mouse_btn_dirty) return;

	// one packet: clamp to the ADB event range so nothing is distorted
	if (dx > 63) dx = 63; else if (dx < -63) dx = -63;
	if (dy > 63) dy = 63; else if (dy < -63) dy = -63;
	int py = -dy;                                // PS/2 y is up-positive
	mouse_strobe ^= 1;
	VERTOPINTERN->ps2_mouse =
		(mouse_strobe << 24) |
		((py & 0xFF) << 16) | ((dx & 0xFF) << 8) |
		((py < 0) ? 0x20 : 0) | ((dx < 0) ? 0x10 : 0) |
		(mouse_btn_down ? 0x01 : 0);
	mouse_btn_sent = mouse_btn_down;
	mouse_btn_dirty = false;
}

// --- open-loop ADB mouse injection (bring-up) -----------------------------
// +mousewiggle=N : emit one relative-move packet every N frames, moving the
// pointer down-and-right.  The click-to-warp path above closes its loop
// against RawMouse ($82C), which nothing maintains before a System boots, so
// it CANNOT exercise the ADB mouse at the flashing-? screen — which is
// exactly where the hardware sits.  This path is unconditional, needs no
// System, and runs headless (adb_mouse_update() is GUI-only).
static int      mouse_wiggle = 0;
static uint64_t mouse_wiggle_last = ~0ull;

// The wiggle also CLICKS: it holds the button down for a run of reports, then
// releases for a run.  Motion-only wiggling cannot reproduce the hardware
// symptom where mouse movement works but button presses never take effect --
// the button is bit 0 of ps2_mouse, carried in the same report as the deltas
// and returned in the same ADB byte (adb.sv: response[0] = {~mouseButton, dy}).
// +mousebtn=N sets the hold/release run length in wiggle events; 0 disables.
static int mouse_btn_period = 0;
static int mouse_wiggle_n   = 0;

static void adb_mouse_wiggle(uint64_t frame) {
	if (!mouse_wiggle) return;
	if (frame == mouse_wiggle_last || (frame % (unsigned)mouse_wiggle)) return;
	mouse_wiggle_last = frame;
	const int dx = 8, py = -8;              // right, and down (PS/2 y is up+)
	int btn = 0;
	if (mouse_btn_period > 0)
		btn = ((mouse_wiggle_n / mouse_btn_period) & 1) ? 1 : 0;
	mouse_wiggle_n++;
	mouse_strobe ^= 1;
	VERTOPINTERN->ps2_mouse =
		(mouse_strobe << 24) |
		((py & 0xFF) << 16) | ((dx & 0xFF) << 8) |
		((py < 0) ? 0x20 : 0) | ((dx < 0) ? 0x10 : 0) |
		(btn ? 0x01 : 0);
}

static void save_screenshot(int frame) {
	char filename[64];
	snprintf(filename, sizeof(filename), "screenshot_f%d.png", frame);
	stbi_write_png(filename, output_width, output_height, 4, output_ptr,
	               output_width * 4);
	printf("Saved %s (%dx%d)\n", filename, output_width, output_height);
}

int verilate() {
	if (!Verilated::gotFinish()) {
		if (main_time < (vluint64_t)initialReset) VERTOPINTERN->reset = 1;
		if (main_time == (vluint64_t)initialReset) VERTOPINTERN->reset = 0;

		clk_sys.Tick();
		VERTOPINTERN->clk_sys = clk_sys.clk;
		VERTOPINTERN->sim_status =
			((opt_tvmode & 1) << 2) | ((opt_noise & 3) << 3);

		if (clk_sys.clk != clk_sys.old) {
			if (clk_sys.clk) {
				control_before_eval();
				input.BeforeEval();
				if (!scsi_disk_file.empty()) blockdevice.BeforeEval(main_time);
			}
			if (clk_sys.clk) speedometer_before_eval();
			top->eval();
			if (clk_sys.clk) dispatched = dispatch_observer.sample(VERTOPINTERN->reset,
				SIMEMU->machine__DOT__cpu__DOT__core__DOT__perf_dispatch_toggle);
			if (clk_sys.clk && !scsi_disk_file.empty()) blockdevice.AfterEval();
			if (clk_sys.clk && !VERTOPINTERN->reset) {
				machine_events();
				speedometer_after_eval(dispatched);
				bracket_step(dispatched);
				fpu_timed_step(dispatched);
				if (!cpu_trace_disabled && (main_time >= trace_after ||
				                            (trace_on_ncr && NCR_REGTRACE))) cpu_trace_step();
				// [EXC] every exception entry that is not an A-line trap or an
				// interrupt: vector, faulting/next pc, format, fault address
				{
					static uint8_t exc_prev_state = 0;
					uint8_t st = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__state;
					if (st == 34 && exc_prev_state != 34) {
						uint8_t vec = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__exc_vec;
						bool irq = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__exc_is_irq;
						if (vec != 10 && !irq)
							printf("[EXC] vec=%u fmt=%u spc=%08X addr=%08X pc_i=%08X @%llu\n", vec,
							       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__exc_fmt,
							       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__exc_spc,
							       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__exc_addr,
							       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i,
							       (unsigned long long)main_time);
					}
					exc_prev_state = st;
				}
				uint32_t hpc = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i;
				if (pc_hist_enable) pc_hist[hpc >> 8]++;
				if (cpu_prof_enable) {
					uint8_t st = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__state;
					prof_state[st]++;
					prof_total++;
					// Observe opcode loads, including consecutive/bypassed decode paths.
					if (dispatched) prof_dispatch++;
					// S_MRD (9) / S_MWR (10) with the request not yet issued
					// because a queue fetch owns the port
					if ((st == 9 || st == 10) &&
					    !SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__m_issued &&
					    SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__epf_pend)
						prof_portwait++;
					prof_prev_state = st;
					if (st == 9 || st == 10) {
						uint8_t cst = SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__cst & 7;
						uint32_t a = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__mem_addr_q;
						int r = prof_region(a);
						if (st == 9) { prof_mrd_cst[cst]++; prof_mrd_region[r]++; }
						else         { prof_mwr_cst[cst]++; prof_mwr_region[r]++; }
					}
					if (SIMEMU->__PVT__machine__DOT__cpu__DOT__g_cache__DOT__cache__DOT__idle_hit) {
						if (SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__mem_instr_q) prof_fast_hit_i++;
						else prof_fast_hit_d++;
					}
					if (st == 3) {
						if (SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__epf_pend) prof_fetch_pend++;
						else prof_fetch_nopend++;
					}
					if (SIMEMU->__PVT__machine__DOT__cpu__DOT__mem_ack) {
						if (SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__mem_instr_q) prof_iack++;
						else {
							int r = prof_region(SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__mem_addr_q);
							if (SIMEMU->__PVT__machine__DOT__cpu__DOT__mem_write) prof_dack_wr[r]++;
							else prof_dack_rd[r]++;
						}
					}
				}
				{
					// RAM write watchpoints: DrvQHdr + the DrvQEl at $B94E
					static const uint32_t watch_addr[] =
						{ 0x308, 0x30C, 0xB948, 0xB94C, 0xB950, 0xB954, 0xB958, 0xB95C };
					static uint32_t watch_prev[8];
					static bool watch_init = false;
					for (int w = 0; w < 8; w++) {
						uint32_t cur = SIMEMU->ram[watch_addr[w] >> 2];
						if (watch_init && cur != watch_prev[w]) {
							printf("[WATCH] %05X: %08X -> %08X pc=%08X cycle=%llu\n",
							       watch_addr[w], watch_prev[w], cur, hpc,
							       (unsigned long long)main_time);
							fflush(stdout);
						}
						watch_prev[w] = cur;
					}
					watch_init = true;
				}
				// edge-triggered: fire on entering the range, so RUN can
				// resume through it without an instant re-stop
				bool pc_in_stop = (hpc >= stop_pc_lo && hpc <= stop_pc_hi);
				if (pc_in_stop && !pc_was_in_stop) {
					printf("[STOP] pc=%08X at cycle %llu\n", hpc,
					       (unsigned long long)main_time);
					for (int r = 0; r < 8; r++)
						printf("[STOP] d%d=%08X a%d=%08X\n", r,
						       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a[r], r,
						       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a[8 + r]);
					printf("[STOP] DSErrCode($AF0)=%04X\n",
					       SIMEMU->ram[0x0AF0 >> 2] >> 16);
					{
						// dump the Drive Queue (DrvQHdr $308): big-endian
						// words packed {b0b1,b2b3} per 32-bit RAM word
						auto r16 = [](uint32_t a) -> uint32_t {
							uint32_t w = SIMEMU->ram[a >> 2];
							return (a & 2) ? (w & 0xFFFF) : (w >> 16);
						};
						auto r32 = [&](uint32_t a) -> uint32_t {
							return (r16(a) << 16) | r16(a + 2);
						};
						uint32_t qh = r32(0x30A);
						printf("[STOP] DrvQHdr qFlags=%04X qHead=%08X qTail=%08X\n",
						       r16(0x308), qh, r32(0x30E));
						for (int n = 0; n < 8 && qh; n++) {
							if (qh >= (32u << 20) || (qh & 1)) {
								printf("[STOP]  node %08X outside RAM\n", qh);
								break;
							}
							printf("[STOP]  DrvQEl@%08X qLink=%08X qType=%04X"
							       " dQDrive=%04X dQRefNum=%04X dQFSID=%04X\n",
							       qh, r32(qh), r16(qh + 4), r16(qh + 6),
							       r16(qh + 8), r16(qh + 10));
							qh = r32(qh);
						}
					}
					fflush(stdout);
					if (cpu_trace_file) fflush(cpu_trace_file);
					run_enable = 0;              // park the RUN checkbox
					Verilated::gotFinish(true);  // halt exactly here
				}
				pc_was_in_stop = pc_in_stop;
				if (main_time >= next_heartbeat) {
					next_heartbeat += heartbeat_every;
					printf("[HB] cycle=%llu pc=%08X instr=%ld a3=%08X d7=%08X\n",
					       (unsigned long long)main_time, hpc, cpu_trace_count,
					       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a[8 + 3],
					       SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a[7]);
					if (cpu_prof_enable) cpu_prof_print();
					fflush(stdout);
				}
			}
		}

		if (clk_sys.IsRising() && !headless)
			audio.Clock(VERTOPINTERN->AUDIO_L, VERTOPINTERN->AUDIO_R);

		if (clk_sys.IsRising() && VERTOPINTERN->CE_PIXEL) {
			uint32_t colour = 0xFF000000 |
				(VERTOPINTERN->VGA_B << 16) |
				(VERTOPINTERN->VGA_G << 8) |
				 VERTOPINTERN->VGA_R;
			int previous_frame = video.count_frame;
			video.Clock(VERTOPINTERN->VGA_HB, VERTOPINTERN->VGA_VB,
			            VERTOPINTERN->VGA_HS, VERTOPINTERN->VGA_VS, colour);
			if (control_shot_pending && video.count_frame != previous_frame) {
				save_screenshot(video.count_frame);
				control_shot_pending = false;
			}
		}

		main_time++;
		return 1;
	}
	return 0;
}

// sim.v keeps its own module class (the public arrays force it), so its
// internals live under rootp->emu rather than flattened into root.
// Physical-address word read mirroring the quadra800 decode.  Valid while
// the CPU runs untranslated (all of ROM startup); once the MMU is on,
// pc_i is logical and entries for non-identity mappings would misread.
static uint16_t sim_read_word(uint32_t addr) {
	uint32_t word;
	bool overlay = VERTOPINTERN->debug_overlay;
	if ((addr >> 28) == 4 || (overlay && addr < 0x400000))
		word = SIMEMU->rom[(addr & 0xFFFFF) >> 2];
	else if (addr < 0x800000)
		word = SIMEMU->ram[addr >> 2];
	else if (addr >= 0xF9000000 && addr < 0xF9200000)
		word = SIMEMU->vram[(addr & 0xFFFFF) >> 2];
	else
		return 0;
	return (addr & 2) ? (uint16_t)word : (uint16_t)(word >> 16);
}

// One trace line per instruction dispatch: pc_i changed inside the core.
static void cpu_trace_step() {
	uint32_t pc = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i;
	if (pc == cpu_trace_last_pc) return;
	cpu_trace_last_pc = pc;

	unsigned short opwords[5];
	for (int k = 0; k < 5; k++) opwords[k] = sim_read_word(pc + 2*k);
	unsigned int len = 2;
	const char* disasm = disassemble_68k_ext_len(pc, opwords, 5, &len);
	cpu_trace_count++;
	if (cpu_trace_file && gui_trace_file)
		fprintf(cpu_trace_file, "%08X: %04X  %-40s @%llu\n", pc, opwords[0], disasm,
		        (unsigned long long)main_time);
	if (trace_max && cpu_trace_count >= trace_max) {
		printf("[TRACE] %ld instructions traced, stopping the trace at cycle %llu\n",
		       cpu_trace_count, (unsigned long long)main_time);
		fflush(stdout);
		if (cpu_trace_file) { fclose(cpu_trace_file); cpu_trace_file = nullptr; }
		cpu_trace_disabled = true;
	}
	if (gui_instr_log)
		console.AddLog("%08X: %04X  %s", pc, opwords[0], disasm);
}

// Bus errors (coalesced per address), overlay switch, core fault/halt.
static void machine_events() {
	static int last_overlay = -1;
	static uint32_t berr_addr = 0xFFFFFFFF;
	static long berr_repeat = 0;
	static int last_fault = 0, last_halted = 0;

	int ov = VERTOPINTERN->debug_overlay;
	if (ov != last_overlay) {
		if (last_overlay != -1 || !ov)
		{
			printf("[MACHINE] overlay %s at cycle %llu\n", ov ? "set" : "cleared",
			       (unsigned long long)main_time);
			console.AddLog("[MACHINE] overlay %s at cycle %llu", ov ? "set" : "cleared",
			       (unsigned long long)main_time);
		}
		last_overlay = ov;
	}

	if (VERTOPINTERN->debug_berr) {
		uint32_t addr = VERTOPINTERN->debug_data_addr;
		if (addr == berr_addr) {
			berr_repeat++;
		} else {
			if (berr_repeat > 1)
				printf("[BERR] %08X repeated x%ld\n", berr_addr, berr_repeat);
			printf("[BERR] addr=%08X pc=%08X cycle=%llu\n", addr,
			       (unsigned)VERTOPINTERN->debug_pc, (unsigned long long)main_time);
			console.AddLog("[BERR] addr=%08X pc=%08X", addr,
			       (unsigned)VERTOPINTERN->debug_pc);
			if (cpu_trace_file)
				fprintf(cpu_trace_file, "[BERR] addr=%08X\n", addr);
			berr_addr = addr;
			berr_repeat = 1;
		}
	}

	int fault = VERTOPINTERN->debug_cpu_fault;
	int halted = VERTOPINTERN->debug_cpu_halted;
	if (halted && !last_halted)
		printf("[LOWMEM] $108=%08X $10C=%08X $2A6=%08X $CFC=%08X\n",
		       SIMEMU->ram[0x108>>2], SIMEMU->ram[0x10C>>2],
		       SIMEMU->ram[0x2A4>>2], SIMEMU->ram[0xCFC>>2]);
	if ((fault && !last_fault) || (halted && !last_halted))
	{
		printf("[MACHINE] %s at cycle %llu pc=%08X\n",
		       halted ? "CPU HALTED (double fault)" : "fault",
		       (unsigned long long)main_time, (unsigned)VERTOPINTERN->debug_pc);
		console.AddLog("[MACHINE] %s pc=%08X",
		       halted ? "CPU HALTED (double fault)" : "fault",
		       (unsigned)VERTOPINTERN->debug_pc);
	}
	last_fault = fault; last_halted = halted;
}

int main(int argc, char** argv, char** env) {
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--headless") || !strcmp(argv[i], "--no-gui")) {
			headless = true;
		} else if (!strcmp(argv[i], "--speedometer-observe") && i + 1 < argc) {
            speedometer_path = argv[++i];
        } else if (!strcmp(argv[i], "--fpu-timed-profile") && i + 1 < argc) {
            fpu_timed_path = argv[++i];
        } else if (!strcmp(argv[i], "--speedometer-limit") && i + 1 < argc) {
            speedometer_limit = strtoull(argv[++i], nullptr, 0);
            if (!speedometer_limit || speedometer_limit > 4096) return 1;
        } else if (!strcmp(argv[i], "--control") && i + 1 < argc) {
			control_file = argv[++i];
		} else if (!strcmp(argv[i], "--cpu-profile") && i + 1 < argc) {
			bracket_file = argv[++i];
		} else if (!strcmp(argv[i], "--no-cpu-trace")) {
			cpu_trace_disabled = true;
		} else if (!strcmp(argv[i], "--trace-on-ncr")) {
			trace_on_ncr = true;
		} else if (!strcmp(argv[i], "--trace-max") && i + 1 < argc) {
			trace_max = strtol(argv[++i], nullptr, 0);
		} else if (!strcmp(argv[i], "--max-cycles") && i + 1 < argc) {
			max_cycles = strtoull(argv[++i], nullptr, 0);
		} else if (!strcmp(argv[i], "--trace-after") && i + 1 < argc) {
			trace_after = strtoull(argv[++i], nullptr, 0);
		} else if (!strcmp(argv[i], "--stop-at-pc") && i + 1 < argc) {
			sscanf(argv[++i], "%x,%x", &stop_pc_lo, &stop_pc_hi);
		} else if (!strcmp(argv[i], "--cd") && i + 1 < argc) {
			scsi_cd_file = argv[++i];
		} else if (!strcmp(argv[i], "--disk") && i + 1 < argc) {
			scsi_disk_file = argv[++i];
		} else if (!strncmp(argv[i], "+mousewiggle=", 13)) {
			mouse_wiggle = atoi(argv[i] + 13);
		} else if (!strncmp(argv[i], "+mousebtn=", 10)) {
			mouse_btn_period = atoi(argv[i] + 10);
		} else if (!strcmp(argv[i], "--hist")) {
			pc_hist_enable = true;
		} else if (!strcmp(argv[i], "--prof")) {
			cpu_prof_enable = true;
		} else if (!strcmp(argv[i], "--screenshot") && i + 1 < argc) {
			screenshot_mode = true;
			std::stringstream ss(argv[++i]);
			std::string n;
			while (std::getline(ss, n, ',')) screenshot_frames.push_back(std::stoi(n));
		} else if (!strcmp(argv[i], "--stop-at-frame") && i + 1 < argc) {
			stop_at_frame = std::stoi(argv[++i]);
		} else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
			printf("wombat33 sim: [--headless] [--screenshot F1,F2,..] [--stop-at-frame N]\n"
			       "              [--no-cpu-trace] [--max-cycles N] [+rom=<hexfile>]\n              [--control PATH] [--cpu-profile FILE]\n");
			return 0;
		}
	}

    if (!fpu_timed_path.empty() && speedometer_path.empty()) {
        fprintf(stderr,"--fpu-timed-profile requires --speedometer-observe\n"); return 1;
    }
    if (!speedometer_path.empty()) {
        speedometer_file.open(speedometer_path);
        if (!speedometer_file) { fprintf(stderr, "cannot open observer output\n"); return 1; }
        speedometer_observer.reset(new speedometer::Observer(speedometer_file, speedometer_limit));
        if(!fpu_timed_path.empty()) {
            fpu_timed_profile.reset(new FpuTimedProfile(fpu_timed_path));
            speedometer_observer->set_fpu_sink([](const speedometer::FpuEvent& e) {
                fpu_timed_profile->event(e);
            });
        }
    }
#ifndef _WIN32
	if (!bracket_file.empty()) {
		std::signal(SIGUSR1, bracket_start_signal);
		std::signal(SIGUSR2, bracket_stop_signal);
		printf("[CPU-PROFILE] SIGUSR1 starts; SIGUSR2 writes %s\n", bracket_file.c_str());
	}
#endif

	if (!control_file.empty()) {
		std::string error;
		if (!sim_control.open(control_file, error)) {
			fprintf(stderr, "[SIM-CONTROL] cannot open %s: %s\n", control_file.c_str(), error.c_str());
			return 1;
		}
		printf("[SIM-CONTROL] reading %s (nonblocking, simulated-cycle pacing)\n", control_file.c_str());
	}

	// The interactive GUI must not fill the disk behind the user's back:
	// the trace file starts enabled only for headless runs — unless a
	// debug window was explicitly requested on the command line.
	gui_trace_file = headless || trace_after != 0;
	if (!cpu_trace_disabled) {
		cpu_trace_file = fopen(cpu_trace_filename, "w");
		if (!cpu_trace_file) { cpu_trace_disabled = true; }
	}

	top = new Vemu();
	Verilated::commandArgs(argc, argv);
	Verilated::traceEverOn(true);

	VERTOPINTERN->clk_sys = 0;
	VERTOPINTERN->reset = 1;
	VERTOPINTERN->ps2_key = 0;
	input.ps2_key = &VERTOPINTERN->ps2_key;
	VERTOPINTERN->ps2_mouse = 0;
	VERTOPINTERN->ioctl_download = 0;
	VERTOPINTERN->ioctl_wr = 0;
	VERTOPINTERN->ioctl_addr = 0;
	VERTOPINTERN->ioctl_dout = 0;
	VERTOPINTERN->ioctl_index = 0;
	top->eval();

	blockdevice.sd_lba[0]      = &VERTOPINTERN->sd_lba0;
	blockdevice.sd_rd          = &VERTOPINTERN->sd_rd;
	blockdevice.sd_wr          = &VERTOPINTERN->sd_wr;
	blockdevice.sd_ack         = &VERTOPINTERN->sd_ack;
	blockdevice.sd_buff_addr   = &VERTOPINTERN->sd_buff_addr;
	blockdevice.sd_blk_cnt     = &VERTOPINTERN->sd_blk_cnt;
	blockdevice.sd_buff_dout   = &VERTOPINTERN->sd_buff_dout;
	blockdevice.sd_buff_din[0] = &VERTOPINTERN->sd_buff_din0;
	blockdevice.sd_lba[2]      = &VERTOPINTERN->sd_lba0;        // CD-ROM: same lba / data bus
	blockdevice.sd_buff_din[2] = &VERTOPINTERN->sd_buff_din0;
	blockdevice.sd_buff_wr     = &VERTOPINTERN->sd_buff_wr;
	blockdevice.img_mounted    = &VERTOPINTERN->img_mounted;
	blockdevice.img_readonly   = &VERTOPINTERN->img_readonly;
	blockdevice.img_size       = &VERTOPINTERN->img_size;
	if (!scsi_disk_file.empty()) blockdevice.MountDisk(scsi_disk_file, 0);
	if (!scsi_cd_file.empty())   blockdevice.MountDisk(scsi_cd_file, 2);

	input.Initialise();
	if (!headless) {
		audio.Initialise();
		if (video.Initialise(windowTitle) == 1) return 1;
	} else {
		// video.Initialise allocates the pixel buffer; headless runs skip
		// the SDL window but still render into the buffer for screenshots.
		// The sim_video globals default to 512x512 until Initialise: size
		// them from the SimVideo instance so frames are not clipped.
		extern unsigned int output_size;
		output_width = video.output_width;
		output_height = video.output_height;
		output_size = output_width * output_height * 4;
		output_ptr = (uint32_t*)calloc(1, output_size);
	}

	bool done = false;
	while (!done) {
		if (!headless) {
			SDL_Event event;
			while (SDL_PollEvent(&event)) {
				ImGui_ImplSDL2_ProcessEvent(&event);
				if (event.type == SDL_QUIT) done = true;
			}

			video.StartFrame();
			input.Read();

			ImGui::NewFrame();
			ImGui::Begin(windowTitle_Control);
			ImGui::SetWindowPos(windowTitle_Control, ImVec2(0, 0), ImGuiCond_Once);
			ImGui::SetWindowSize(windowTitle_Control, ImVec2(500, 230), ImGuiCond_Once);
			if (ImGui::Button("Reset simulation")) { main_time = 0; }
			ImGui::SameLine();
			if (ImGui::Button("Reset core")) {
				VERTOPINTERN->reset = 1;
				for (int i = 0; i < 8; i++) verilate();
				VERTOPINTERN->reset = 0;
			}
			ImGui::Checkbox("RUN", &run_enable);
			ImGui::SameLine();
			ImGui::Checkbox("Instr log", &gui_instr_log);
			ImGui::SameLine();
			ImGui::Checkbox("Trace file", &gui_trace_file);
			ImGui::SliderInt("Batch size", &batchSize, 1000, 1000000);
			if (single_step) single_step = 0;
			if (ImGui::Button("Single step")) single_step = 1;
			ImGui::SameLine();
			if (multi_step) multi_step = 0;
			if (ImGui::Button("Multi step")) multi_step = 1;
			ImGui::SameLine();
			ImGui::SliderInt("Steps", &multi_step_amount, 8, 1024);
			ImGui::Separator();
			ImGui::Text("Frame %06d  %.1f fps  %dx%d", video.count_frame,
			            video.stats_fps, video.stats_xMax - video.stats_xMin + 1,
			            video.stats_yMax - video.stats_yMin + 1);
			ImGui::End();

			// Machine panel: system info + live CPU state
			ImGui::Begin("Machine");
			ImGui::SetWindowPos("Machine", ImVec2(0, 240), ImGuiCond_Once);
			ImGui::SetWindowSize("Machine", ImVec2(500, 330), ImGuiCond_Once);
			{
				uint32_t pc  = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i;
				uint16_t ir  = VERTOPINTERN->debug_opcode;
				uint16_t sr  = VERTOPINTERN->debug_sr;
				// the MLAB regfile (2026-09-17): one bank, D0-D7 then A0-A7
				auto &ds = SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a;
				auto *as = &SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a[8];
				ImGui::Text("Quadra 800 — 68040 @ 33 MHz, 32 MB RAM, 1 MB ROM, 1 MB VRAM");
				ImGui::Text("640x480, 256 colors max (DAFB II)");
				ImGui::Text("overlay=%d  cycle=%llu  instr=%ld",
				            (int)VERTOPINTERN->debug_overlay,
				            (unsigned long long)main_time, cpu_trace_count);
				ImGui::Separator();
				unsigned short opw[5];
				for (int k = 0; k < 5; k++) opw[k] = sim_read_word(pc + 2*k);
				unsigned int dlen = 2;
				ImGui::Text("PC %08X  IR %04X  SR %04X  %s", pc, ir, sr,
				            disassemble_68k_ext_len(pc, opw, 5, &dlen));
				for (int r = 0; r < 8; r += 4)
					ImGui::Text("D%d %08X  D%d %08X  D%d %08X  D%d %08X",
					            r, ds[r], r+1, ds[r+1], r+2, ds[r+2], r+3, ds[r+3]);
				ImGui::Text("A0 %08X  A1 %08X  A2 %08X  A3 %08X",
				            as[0], as[1], as[2], as[3]);
				ImGui::Text("A4 %08X  A5 %08X  A6 %08X  A7 %08X",
				            as[4], as[5], as[6],
				            (uint32_t)VERTOPINTERN->debug_a7);
				ImGui::Separator();
				ImGui::TextDisabled("SCC / SCSI / floppy / ADB panels arrive with their devices");
			}
			ImGui::End();

			console.Draw("Debug log", &showDebugLog, ImVec2(500, 400));
			ImGui::SetWindowPos("Debug log", ImVec2(0, 580), ImGuiCond_Once);

			ImGui::Begin("Audio output");
			ImGui::SetWindowPos("Audio output", ImVec2(510, 540), ImGuiCond_Once);
			ImGui::SetWindowSize("Audio output", ImVec2(680, 250), ImGuiCond_Once);
			{
				audio.CollectDebug((signed short)VERTOPINTERN->AUDIO_L,
				                   (signed short)VERTOPINTERN->AUDIO_R);
				float channelWidth = 320.0f;
				ImPlot::CreateContext();
				if (ImPlot::BeginPlot("Audio - L", ImVec2(channelWidth, 220),
				        ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
					ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_l,
					                   audio.debug_max_samples, audio.debug_pos);
					ImPlot::EndPlot();
				}
				ImGui::SameLine();
				if (ImPlot::BeginPlot("Audio - R", ImVec2(channelWidth, 220),
				        ImPlotFlags_NoLegend | ImPlotFlags_NoMenus | ImPlotFlags_NoTitle)) {
					ImPlot::PlotStairs("", audio.debug_positions, audio.debug_wave_r,
					                   audio.debug_max_samples, audio.debug_pos);
					ImPlot::EndPlot();
				}
				ImPlot::DestroyContext();
			}
			ImGui::End();

			ImGui::Begin(windowTitle_Video);
			ImGui::SetWindowPos(windowTitle_Video, ImVec2(510, 0), ImGuiCond_Once);
			ImGui::SetWindowSize(windowTitle_Video,
				ImVec2(video.output_width * vga_scale + 24,
				       video.output_height * vga_scale + 46), ImGuiCond_Once);
			ImGui::SliderFloat("Zoom", &vga_scale, 0.5, 4.0);
			ImGui::Image(video.texture_id,
				ImVec2(video.output_width * vga_scale,
				       video.output_height * vga_scale));
			// clicks/drags on the image drive the ADB mouse: the click
			// point becomes the warp target; button state rides along
			if (ImGui::IsItemHovered()) {
				bool down = ImGui::IsMouseDown(ImGuiMouseButton_Left);
				if (down || ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
					ImVec2 rmin = ImGui::GetItemRectMin();
					ImVec2 mp = ImGui::GetMousePos();
					mouse_warp_x = (int)((mp.x - rmin.x) / vga_scale);
					mouse_warp_y = (int)((mp.y - rmin.y) / vga_scale);
					mouse_stalled = 0;
				}
				if (down != mouse_btn_sent) {
					mouse_btn_down = down;
					mouse_btn_dirty = true;
				}
			}
			else if (mouse_btn_sent) {
				// pointer left the image with the button down: release it
				mouse_btn_down = false;
				mouse_btn_dirty = true;
			}
			ImGui::End();

			adb_mouse_update();
			video.UpdateTexture();
		}

		adb_mouse_wiggle(video.count_frame);

		if (screenshot_mode) {
			auto it = std::find(screenshot_frames.begin(), screenshot_frames.end(),
			                    (int)video.count_frame);
			if (it != screenshot_frames.end()) {
				save_screenshot(video.count_frame);
				screenshot_frames.erase(it);
			}
		}
		if (stop_at_frame >= 0 && (int)video.count_frame >= stop_at_frame) {
			printf("Reached frame %d, exiting\n", stop_at_frame);
			break;
		}
		if (max_cycles && main_time >= max_cycles) {
			printf("Reached %llu cycles, exiting\n", (unsigned long long)main_time);
			break;
		}

		// run_enable true with finish latched can only mean the user
		// re-checked RUN after a [STOP]: clear the latch and resume
		if (Verilated::gotFinish() && run_enable) Verilated::gotFinish(false);
		if (Verilated::gotFinish()) run_enable = 0;
		if (run_enable)
			for (int step = 0; step < batchSize; step++) verilate();
		else {
			if (single_step) verilate();
			if (multi_step)
				for (int step = 0; step < multi_step_amount; step++) verilate();
		}

		if (headless && Verilated::gotFinish()) done = true;
	}

	fpu_timed_finish();
	if (speedometer_observer) speedometer_observer->summary();
	if (bracket_gate.active()) { bracket_dump(); bracket_gate.stop(); }
	if (cpu_trace_file) {
		printf("CPU trace: %ld instructions, last pc=%08X (%s)\n",
		       cpu_trace_count, cpu_trace_last_pc, cpu_trace_filename);
		fclose(cpu_trace_file);
	}
	{
		std::vector<int> idx;
		for (int i = 0; i < (1 << 24); i++) if (pc_hist[i]) idx.push_back(i);
		std::sort(idx.begin(), idx.end(),
		          [](int a, int b) { return pc_hist[a] > pc_hist[b]; });
		printf("PC histogram (top 15 of %zu 256-byte buckets):\n", idx.size());
		for (size_t i = 0; i < idx.size() && i < 15; i++)
			printf("  %08X: %u cycles\n", pc_hist_pc(idx[i]), pc_hist[idx[i]]);
	}
	if (!headless) { audio.CleanUp(); video.CleanUp(); input.CleanUp(); }
    if(std::getenv("SPEEDOMETER_FIXTURE_CHECK")) {
        const uint32_t selector0=SIMEMU->ram[0x000fbea8/4]&0xffff;
        const uint32_t selector1=SIMEMU->ram[0x000fbeac/4]>>16;
        const uint32_t magic=SIMEMU->ram[0x00100100/4];
        const uint32_t d0=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__bank_a[0];
        const uint32_t sp=SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__regfile__DOT__isp;
        const uint32_t expected_d0=std::getenv("SPEEDOMETER_FIXTURE_D0")?std::strtoul(std::getenv("SPEEDOMETER_FIXTURE_D0"),nullptr,0):1;
        const bool pass=selector0==4 && selector1==0x42 && magic==0x600d0042 && d0==expected_d0 && sp==0x00200000;
        printf("FIXTURE_CHECK %s selector0=%04x selector1=%04x magic=%08x D0=%08x SP=%08x\n",
            pass?"PASS":"FAIL",selector0,selector1,magic,d0,sp);
        if(!pass)return 4;
    }
	top->final();
	delete top;
	return 0;
}
