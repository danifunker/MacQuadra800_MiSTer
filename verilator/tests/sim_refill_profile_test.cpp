#include "../sim_refill_profile.h"
#include <cassert>

int main() {
	assert(SimRefillProfile::region(0x0fffffff) == 0);
	assert(SimRefillProfile::region(0x10000000) == 0);
	assert(SimRefillProfile::region(0x3fffffff) == 0);
	assert(SimRefillProfile::region(0x40000000) == 1);
	assert(SimRefillProfile::region(0x4fffffff) == 1);
	assert(SimRefillProfile::region(0x50000000) == 2);
	SimRefillProfile p;
	// A bracket that opens in mid-fill contributes samples, but no full span.
	p.sample(4, false, 0x00001000, 2, true, true, false, true);
	p.sample(5, false, 0x00001000, 3, false, true, false, false);
	p.sample(0, false, 0x00001000, 3, false, true, false, false);
	assert(p.partial_at_start == 1 && p.completed[0][0] == 0);
	assert(p.fill_samples[0][0][2][1][1] == 1);
	assert(p.mrd_overlap_samples[0][0] == 1);

	// Complete ROM instruction fill: four sampled fill clocks plus tag write.
	p.sample(4, true, 0x40000000, 0, false, false, true, false);
	p.sample(4, true, 0x40000000, 1, true, true, false, false);
	p.sample(4, true, 0x40000000, 2, false, true, true, false);
	p.sample(4, true, 0x40000000, 3, true, true, false, false);
	p.sample(5, true, 0x40000000, 3, false, true, false, false);
	p.sample(0, true, 0x40000000, 3, false, true, false, false);
	assert(p.fill_entries[1][1] == 1 && p.completed[1][1] == 1);
	assert(p.tagwrite_samples[1][1] == 1 && p.local_match_samples[1][1] == 2);
	assert(p.issued_state_samples[1][1] == 2 && p.setup_state_samples[1][1] == 0);
	assert(p.duration_hist.at((5ull << 3) | (1 << 2) | 1) == 1);

	// Error exit and bracket stop are excluded from the duration histogram.
	p.sample(4, false, 0x50000000, 0, false, false, false, false);
	p.sample(2, false, 0x50000000, 0, false, false, false, false);
	assert(p.aborted == 1 && p.completed[0][2] == 0);
	p.sample(4, false, 0x00002000, 0, false, false, false, false);
	p.stop();
	assert(p.partial_at_end == 1 && p.duration_hist.size() == 1);
	p.reset();
	assert(p.duration_hist.empty() && p.partial_at_start == 0 && p.fill_entries[1][1] == 0);
}
