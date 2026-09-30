#pragma once

#include <cstdint>
#include <map>

// One observation per rising edge, after Verilator eval(). These are sampled
// register/combination states, not counts of memory requests or bus acks.
struct SimRefillProfile {
	// bank: data/instruction; region: RAM/ROM/other; beat: fill_cnt 0..3;
	// issued and acked are the cache's registered state at the sample.
	uint64_t fill_samples[2][3][4][2][2]{};
	uint64_t fill_entries[2][3]{};
	uint64_t tagwrite_samples[2][3]{};
	uint64_t local_match_samples[2][3]{};
	uint64_t issued_state_samples[2][3]{};
	uint64_t setup_state_samples[2][3]{};
	uint64_t mrd_overlap_samples[2][3]{};
	uint64_t completed[2][3]{};
	uint64_t partial_at_start = 0, partial_at_end = 0, aborted = 0;
	// Only complete C_FILL..C_TAGW spans with both boundaries observed.
	// Key packs duration, bank and region; insertion happens once per fill.
	std::map<uint64_t, uint64_t> duration_hist;

	bool prev_valid = false, span_active = false, span_complete_start = false;
	uint8_t prev_cst = 0, span_bank = 0, span_region = 0;
	uint64_t span_clocks = 0;

	static uint8_t region(uint32_t addr) {
		// Match wombat_cpu.sv cache_allow's physical RAM/ROM decode.
		return addr < 0x40000000u ? 0 : (addr >> 28) == 4 ? 1 : 2;
	}

	void reset() { *this = SimRefillProfile{}; }

	void sample(uint8_t cst, bool instr, uint32_t addr, uint8_t fill_cnt,
	            bool issued, bool acked, bool line_match, bool core_mrd) {
		const uint8_t bank = instr ? 1 : 0, reg = region(addr);
		const bool active = cst == 4 || cst == 5;
		if (span_active && !active) {
			if (span_complete_start && prev_cst == 5 && cst == 0) {
				completed[span_bank][span_region]++;
				duration_hist[(span_clocks << 3) | (span_bank << 2) | span_region]++;
			} else if (span_complete_start) {
				aborted++;
			}
			span_active = false;
		}
		if (active && !span_active) {
			span_active = true;
			span_complete_start = prev_valid && cst == 4;
			if (!span_complete_start) partial_at_start++;
			span_bank = bank;
			span_region = reg;
			span_clocks = 0;
			if (cst == 4 && span_complete_start) fill_entries[bank][reg]++;
		}
		if (active) {
			span_clocks++;
			if (cst == 4) {
				fill_samples[bank][reg][fill_cnt & 3][issued][acked]++;
				if (line_match) local_match_samples[bank][reg]++;
				if (issued) issued_state_samples[bank][reg]++;
				else if (!line_match) setup_state_samples[bank][reg]++;
				if (core_mrd) mrd_overlap_samples[bank][reg]++;
			} else {
				tagwrite_samples[bank][reg]++;
			}
		}
		prev_cst = cst;
		prev_valid = true;
	}

	void stop() {
		if (span_active) partial_at_end++;
		span_active = false;
	}
};
