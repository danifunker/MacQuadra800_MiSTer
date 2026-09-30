// fpu_window_monitor.h -- passive, simulation-only segment profiler used by
// scratch/fpu_subtest_breakdown_20260928 (never production RTL).
//
// The profiled bracket (the existing "profile start" / "profile stop"
// control commands) is cut into SEGMENTS.  A segment ends
//   * at the primary dispatch of a marker A-line trap (Microseconds $A193,
//     TickCount $A975, InsTime $A058, InsXTime $A458, PrimeTime $A05A,
//     RmvTime $A059), the trap cycle itself starting the next segment, or
//   * every `period` monitor cycles (periodic boundary, reason 'P').
// Each segment dumps its nonzero counters, so any window whose ends are
// segment boundaries is reconstructed exactly by summing segments offline.
//
// Inputs are sampled after the rising-edge eval, exactly like the existing
// --cpu-profile bracket (sim.v ties CPU CE high: one sample = one CPU clock).
#ifndef FPU_WINDOW_MONITOR_H
#define FPU_WINDOW_MONITOR_H

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <vector>

struct FwmInputs {
	uint8_t  state = 0;      // core state (8 bit)
	uint8_t  fst = 0;        // ap040_fpu fst (5 bit)
	uint8_t  fpop = 0;       // ap040_fpu r_op (7 bit)
	uint8_t  cst = 0;        // ap040_cache cst (4 bit with XSTORE)
	bool     r_bank = false; // cache refill bank: 1 = instruction
	uint8_t  m_ret = 0;      // core r_m_ret (return state of S_MRD/S_MWR)
	uint8_t  exc_vec = 0;
	uint16_t ir = 0, imm = 0;
	uint32_t pc_i = 0, a7 = 0;
	bool dispatch = false, fpu_bg = false, fpu_done = false;
	uint8_t  sb_count = 0;
	bool sb_req = false, sb_push = false, sb_ack = false, bus_req = false, bus_wr = false;
};

class FpuWindowMonitor {
public:
	// core state encodings (ap040_core.v localparams)
	enum : uint8_t {
		S_FETCH = 3, S_MRD = 9, S_MWR = 10, S_EXC0 = 34, S_EXC_VEC = 41, S_EXC_JMP = 42,
		S_RTE_SR = 43, S_RTE_FIN2 = 47, S_AERR0 = 108, S_FSAVE1 = 151, S_FREST1 = 152,
		S_FPU_DEC = 153, S_FPU_RD = 158, S_FPU_WR = 161, S_FBCC = 167, S_FSCC0 = 168,
		S_MRD_B = 175, S_MWR_B = 176, S_POST_EXC = 181, S_EXC0_F2 = 191, S_EXC0_F3 = 192,
		S_EXC0_F4 = 193, S_POST_EXC_F2 = 194, S_POST_EXC_F3 = 195, S_POST_EXC_F4 = 196
	};
	enum : uint8_t { C_FILL = 4, C_TAGW = 5 };

	bool open(const char* path, uint64_t period) {
		f_ = fopen(path, "w");
		period_ = period ? period : 500000;
		if (f_) fprintf(f_, "# fpu_window_monitor v1 period=%llu\n", (unsigned long long)period_);
		return f_ != nullptr;
	}
	bool enabled() const { return f_ != nullptr; }

	void start(uint64_t sim_time) {
		if (!f_) return;
		active_ = true; cyc_ = 0; seg_start_ = 0; last_periodic_ = 0; seg_idx_ = 0;
		start_time_ = sim_time; prev_valid_ = false; stack_.clear();
		fp_open_ = false; exc_pending_ = false; pc_run_bucket_ = ~0u; pc_run_len_ = 0;
		reset_seg();
		seg_reason_ = 'B'; seg_op_ = 0; seg_pc_ = 0; seg_a7_ = 0;
		fprintf(f_, "START\t%llu\n", (unsigned long long)sim_time);
		fflush(f_);
	}

	void stop() {
		if (!f_ || !active_) return;
		close_fp();
		flush_pc_run();
		dump_seg('E', 0, 0, 0);
		fprintf(f_, "STOP\t%llu\tcycles=%llu\tstack_left=%zu\n", (unsigned long long)cyc_,
		        (unsigned long long)cyc_, stack_.size());
		fflush(f_);
		active_ = false;
	}

	void sample(const FwmInputs& in) {
		if (!f_ || !active_) return;
		// ---- boundaries (the triggering cycle belongs to the NEW segment)
		const bool aline = in.dispatch && (in.ir & 0xF000) == 0xA000;
		if (aline && is_marker(in.ir)) {
			close_fp();
			flush_pc_run();
			dump_seg('T', in.ir, in.pc_i, in.a7);
		}
		else if (cyc_ - last_periodic_ >= period_) {
			close_fp();
			flush_pc_run();
			dump_seg('P', 0, in.pc_i, in.a7);
			last_periodic_ = cyc_;
		}

		const uint8_t st = in.state;
		const bool entered = !prev_valid_ || st != prev_state_;
		const uint8_t cst = in.cst & 15;
		const bool fill_entered = cst == C_FILL && (!prev_valid_ || prev_cst_ != C_FILL);
		const bool tagw_entered = cst == C_TAGW && (!prev_valid_ || prev_cst_ != C_TAGW);

		// ---- per-cycle occupancy
		s_.cycles++;
		s_.state[st]++;
		s_.fst[in.fst & 31]++;
		s_.cst[cst][in.r_bank ? 1 : 0]++;
		if (fill_entered) s_.fill_start[in.r_bank ? 1 : 0]++;
		if (tagw_entered) s_.tagw_start[in.r_bank ? 1 : 0]++;
		if (in.fst != 0) {
			s_.fst_op[((uint32_t)(in.fst & 31) << 8) | (in.fpop & 0x7F)]++;
			if (in.fpu_bg) s_.fpu_busy_bg++;
			if (st >= S_FPU_DEC && st <= 177 && st != S_FBCC) s_.fpu_busy_cpu_fpstate++;
		}
		if (in.fpu_bg) s_.fpu_bg_cycles++;
		if (st == S_FPU_DEC) {
			if (in.fpu_bg && !in.fpu_done) s_.fpdec_wait_bg++;
			else s_.fpdec_other++;
		}
		if ((st == S_FBCC || st == S_FSCC0) && in.fpu_bg) s_.fpcc_wait_bg++;
		if ((st == S_FSAVE1 || st == S_FREST1) && in.fpu_bg) s_.fsave_wait_bg++;
		if ((st == S_EXC0 || st == S_EXC0_F2 || st == S_EXC0_F3 || st == S_EXC0_F4) && in.fpu_bg)
			s_.exc0_wait_bg++;
		s_.st_cst[st][cst]++;
		if (st == S_MRD || st == S_MRD_B) s_.mrd_ret[in.m_ret]++;
		if (st == S_MWR || st == S_MWR_B) s_.mwr_ret[in.m_ret]++;
		if (in.sb_count) s_.sb_nonempty++;
		if (in.sb_req && !in.sb_push && !in.sb_ack) s_.sb_full++;
		if (in.bus_req && !in.bus_wr && in.sb_count) s_.read_behind_store++;
		if (in.sb_push) s_.sb_pushes++;
		if (in.pc_i >= 0x40000000u && in.pc_i < 0x50000000u) s_.rom_pc_cycles++;
		// PC occupancy in 256-byte buckets, run-length accumulated
		const uint32_t bucket = in.pc_i >> 8;
		if (bucket != pc_run_bucket_) { flush_pc_run(); pc_run_bucket_ = bucket; }
		pc_run_len_++;

		// ---- dispatch-level events
		if (in.dispatch) {
			s_.dispatches++;
			s_.opcode[in.ir]++;
			close_fp();
			if (aline) s_.aline[in.ir]++;
			if ((in.ir & 0xFE00) == 0xF200) {          // coprocessor id 1 (FPU)
				switch ((in.ir >> 6) & 7) {
				case 0: s_.cpgen_dispatch++; break;
				case 1: s_.fscc_dispatch++; break;
				case 2: case 3: s_.fbcc_dispatch++; break;
				case 4: s_.fsave_dispatch++; break;
				case 5: s_.frestore_dispatch++; break;
				default: s_.fline_other_dispatch++; break;
				}
			}
		}

		// ---- FP instruction forms: one per S_FPU_DEC entry
		if (st == S_FPU_DEC && entered) {
			close_fp();
			fp_open_ = true;
			fp_key_ = ((uint32_t)in.ir << 16) | in.imm;
			fp_t0_ = cyc_;
			s_.fp_entries++;
			if (in.fpu_bg && !in.fpu_done) s_.fp_waited++;
			s_.fp_form[fp_key_]++;
		}

		// ---- exceptions: start, vector fetch, handler entry, RTE match
		const bool exc_entry_state = st == S_EXC0 || st == S_EXC0_F2 || st == S_EXC0_F3 ||
			st == S_EXC0_F4 || st == S_AERR0 || st == S_POST_EXC || st == S_POST_EXC_F2 ||
			st == S_POST_EXC_F3 || st == S_POST_EXC_F4;
		if (exc_entry_state && !exc_pending_) { exc_pending_ = true; exc_t0_ = cyc_; }
		if (st == S_EXC_VEC && entered) {
			close_fp();
			Rec r;
			r.vec = in.exc_vec;
			r.t0 = exc_pending_ ? exc_t0_ : cyc_;
			exc_pending_ = false;
			r.key = ((uint32_t)in.exc_vec << 16) |
				((in.exc_vec == 11 || in.exc_vec == 55) ? in.imm : (in.exc_vec == 10 ? in.ir : 0));
			r.sp = 0; r.sp_valid = false;
			s_.exc[in.exc_vec]++;
			s_.exc_key[r.key]++;
			if (stack_.size() >= 4096) { stack_.erase(stack_.begin()); s_.exc_stack_drops++; }
			stack_.push_back(r);
		}
		if (st == S_EXC_JMP && entered && !stack_.empty() && !stack_.back().sp_valid) {
			stack_.back().sp = in.a7; stack_.back().sp_valid = true;
		}
		if (st == S_RTE_SR && entered && prev_state_ != S_RTE_FIN2) {
			s_.rte_count++;
			const uint32_t sp = in.a7;
			while (!stack_.empty() && stack_.back().sp_valid && stack_.back().sp < sp) {
				s_.exc_abandoned[stack_.back().vec]++;
				stack_.pop_back();
			}
			if (!stack_.empty() && stack_.back().sp_valid && stack_.back().sp == sp) {
				const Rec& r = stack_.back();
				const uint64_t d = cyc_ - r.t0;
				s_.exc_matched[r.vec]++;
				s_.exc_dur[r.vec] += d;
				s_.exc_key_dur[r.key] += d;
				s_.exc_key_matched[r.key]++;
				stack_.pop_back();
			}
			else s_.rte_unmatched++;
		}

		prev_state_ = st; prev_cst_ = cst; prev_valid_ = true;
		cyc_++;
	}

private:
	struct Rec { uint8_t vec; uint64_t t0; uint32_t key; uint32_t sp; bool sp_valid; };
	struct Seg {
		uint64_t cycles, dispatches, fp_entries;
		uint64_t state[256], fst[32], cst[16][2], fill_start[2], tagw_start[2];
		uint64_t mrd_ret[256], mwr_ret[256], st_cst[256][16], fp_waited;
		uint64_t exc[256], exc_matched[256], exc_dur[256], exc_abandoned[256];
		uint64_t fpu_busy_bg, fpu_busy_cpu_fpstate, fpu_bg_cycles, fpdec_wait_bg, fpdec_other;
		uint64_t fpcc_wait_bg, fsave_wait_bg, exc0_wait_bg;
		uint64_t sb_nonempty, sb_full, read_behind_store, sb_pushes, rom_pc_cycles;
		uint64_t cpgen_dispatch, fscc_dispatch, fbcc_dispatch, fsave_dispatch, frestore_dispatch,
			fline_other_dispatch;
		uint64_t rte_count, rte_unmatched, exc_stack_drops;
		std::map<uint32_t, uint64_t> fst_op, opcode, aline, fp_form, fp_form_cyc, pc,
			exc_key, exc_key_dur, exc_key_matched;
	};

	static bool is_marker(uint16_t op) {
		return op == 0xA193 || op == 0xA975 || op == 0xA058 || op == 0xA458 ||
			op == 0xA05A || op == 0xA059;
	}
	void reset_seg() {
		Seg z{};
		// scalars/arrays zeroed by value-init; maps start empty
		s_ = std::move(z);
	}
	void close_fp() {
		if (!fp_open_) return;
		s_.fp_form_cyc[fp_key_] += cyc_ - fp_t0_;
		fp_open_ = false;
	}
	void flush_pc_run() {
		if (pc_run_len_) s_.pc[pc_run_bucket_] += pc_run_len_;
		pc_run_len_ = 0;
	}
	void put(const char* name, uint64_t v) {
		if (v) fprintf(f_, "%s\t%llu\n", name, (unsigned long long)v);
	}
	void put_arr(const char* name, const uint64_t* a, int n) {
		for (int i = 0; i < n; i++)
			if (a[i]) fprintf(f_, "%s:%d\t%llu\n", name, i, (unsigned long long)a[i]);
	}
	void put_map(const char* name, const std::map<uint32_t, uint64_t>& m) {
		for (const auto& kv : m)
			if (kv.second) fprintf(f_, "%s:%X\t%llu\n", name, kv.first, (unsigned long long)kv.second);
	}
	void dump_seg(char next_reason, uint16_t next_op, uint32_t next_pc, uint32_t next_a7) {
		// the segment just ended is [seg_start_, cyc_)
		fprintf(f_, "SEG\t%llu\t%llu\t%llu\t%c\t%04X\t%08X\t%08X\n",
		        (unsigned long long)seg_idx_, (unsigned long long)seg_start_,
		        (unsigned long long)cyc_, seg_reason_, seg_op_, seg_pc_, seg_a7_);
		put("cycles", s_.cycles); put("dispatches", s_.dispatches); put("fp_entries", s_.fp_entries);
		put_arr("st", s_.state, 256); put_arr("fst", s_.fst, 32);
		for (int c = 0; c < 16; c++)
			for (int b = 0; b < 2; b++)
				if (s_.cst[c][b]) fprintf(f_, "cst:%d:%d\t%llu\n", c, b, (unsigned long long)s_.cst[c][b]);
		put_arr("fill_start", s_.fill_start, 2); put_arr("tagw_start", s_.tagw_start, 2);
		put_arr("mrd_ret", s_.mrd_ret, 256); put_arr("mwr_ret", s_.mwr_ret, 256);
		for (int a = 0; a < 256; a++)
			for (int c = 0; c < 16; c++)
				if (s_.st_cst[a][c]) fprintf(f_, "stc:%d:%d\t%llu\n", a, c, (unsigned long long)s_.st_cst[a][c]);
		put("fp_waited", s_.fp_waited);
		put_arr("exc", s_.exc, 256); put_arr("exc_matched", s_.exc_matched, 256);
		put_arr("exc_dur", s_.exc_dur, 256); put_arr("exc_abandoned", s_.exc_abandoned, 256);
		put("fpu_busy_bg", s_.fpu_busy_bg); put("fpu_busy_cpu_fpstate", s_.fpu_busy_cpu_fpstate);
		put("fpu_bg_cycles", s_.fpu_bg_cycles); put("fpdec_wait_bg", s_.fpdec_wait_bg);
		put("fpdec_other", s_.fpdec_other); put("fpcc_wait_bg", s_.fpcc_wait_bg);
		put("fsave_wait_bg", s_.fsave_wait_bg); put("exc0_wait_bg", s_.exc0_wait_bg);
		put("sb_nonempty", s_.sb_nonempty); put("sb_full", s_.sb_full);
		put("read_behind_store", s_.read_behind_store); put("sb_pushes", s_.sb_pushes);
		put("rom_pc_cycles", s_.rom_pc_cycles);
		put("cpgen_dispatch", s_.cpgen_dispatch); put("fscc_dispatch", s_.fscc_dispatch);
		put("fbcc_dispatch", s_.fbcc_dispatch); put("fsave_dispatch", s_.fsave_dispatch);
		put("frestore_dispatch", s_.frestore_dispatch); put("fline_other_dispatch", s_.fline_other_dispatch);
		put("rte_count", s_.rte_count); put("rte_unmatched", s_.rte_unmatched);
		put("exc_stack_drops", s_.exc_stack_drops);
		put_map("fso", s_.fst_op); put_map("op", s_.opcode); put_map("al", s_.aline);
		put_map("fpf", s_.fp_form); put_map("fpc", s_.fp_form_cyc); put_map("pc", s_.pc);
		put_map("exk", s_.exc_key); put_map("exkd", s_.exc_key_dur); put_map("exkm", s_.exc_key_matched);
		fprintf(f_, "END\n");
		if (next_reason == 'T') fflush(f_);
		seg_idx_++;
		seg_start_ = cyc_;
		seg_reason_ = next_reason; seg_op_ = next_op; seg_pc_ = next_pc; seg_a7_ = next_a7;
		reset_seg();
	}

	FILE* f_ = nullptr;
	bool active_ = false;
	uint64_t period_ = 500000, cyc_ = 0, seg_start_ = 0, last_periodic_ = 0, seg_idx_ = 0, start_time_ = 0;
	char seg_reason_ = 'B'; uint16_t seg_op_ = 0; uint32_t seg_pc_ = 0, seg_a7_ = 0;
	bool prev_valid_ = false; uint8_t prev_state_ = 0, prev_cst_ = 0;
	std::vector<Rec> stack_;
	bool fp_open_ = false; uint32_t fp_key_ = 0; uint64_t fp_t0_ = 0;
	bool exc_pending_ = false; uint64_t exc_t0_ = 0;
	uint32_t pc_run_bucket_ = ~0u; uint64_t pc_run_len_ = 0;
	Seg s_{};
};

#endif
