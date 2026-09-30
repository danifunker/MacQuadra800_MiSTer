#include "window_counters.h"

#include <cassert>
#include <cstdint>
#include <numeric>

template <std::size_t N>
static std::uint64_t sum(const std::array<std::uint64_t, N>& values) {
    return std::accumulate(values.begin(), values.end(), std::uint64_t{0});
}

static void test_samples_and_overlaps() {
    WindowCounters c;

    // Simultaneously contributes to both overlap counters and to the FPU-op
    // busy histogram; these are intentionally independent tallies.
    assert(c.sample({153, 4, 1, 17, true, false, false, false}));
    // GO sample contributes to the dispatch count, but not decode blocking.
    assert(c.sample({160, 4, 0, 127, true, true, true, true}));
    // An acknowledged MRD/fill overlap with an FPU operation in progress.
    assert(c.sample({9, 4, 31, 127, false, false, true, true}));
    // Same overlap without acknowledgement exercises the unacked subset.
    assert(c.sample({9, 4, 0, 127, false, false, false, false}));
    // Background with completed FPU is not a blocking-decode sample.
    assert(c.sample({153, 2, 2, 3, true, true, false, false}));

    assert(c.total == 5);
    assert(c.dispatched == 2);
    assert(c.core[153] == 2 && c.core[160] == 1 && c.core[9] == 2);
    assert(c.cache[4] == 4 && c.cache[2] == 1);
    assert(c.fpu[1] == 1 && c.fpu[0] == 2 && c.fpu[31] == 1 && c.fpu[2] == 1);
    assert(c.fpu_op_busy[17] == 1 && c.fpu_op_busy[3] == 1);
    assert(c.fpu_op_busy[127] == 1); // state 31 busy; state 0 is excluded
    assert(c.bg_samples == 3);
    assert(c.blocking_decode == 1);
    assert(c.go_samples == 1);
    assert(c.mrd_fill_overlap == 2);
    assert(c.mrd_fill_unacked_overlap == 1);
    assert(sum(c.core) == c.total);
    assert(sum(c.cache) == c.total);
    assert(sum(c.fpu) == c.total);
    assert(sum(c.fpu_op_busy) == 3);
}

static void test_invalid_samples_are_atomic() {
    WindowCounters c;
    assert(c.sample({9, 4, 1, 1, true, false, true, false}));
    const WindowCounters before = c;

    assert(!c.sample({9, 16, 1, 1, true, false, true, false}));
    assert(!c.sample({9, 4, 32, 1, true, false, true, false}));
    assert(!c.sample({9, 4, 1, 128, true, false, true, false}));

    assert(c.total == before.total);
    assert(c.dispatched == before.dispatched);
    assert(c.core == before.core);
    assert(c.cache == before.cache);
    assert(c.fpu == before.fpu);
    assert(c.fpu_op_busy == before.fpu_op_busy);
    assert(c.bg_samples == before.bg_samples);
    assert(c.blocking_decode == before.blocking_decode);
    assert(c.go_samples == before.go_samples);
    assert(c.mrd_fill_overlap == before.mrd_fill_overlap);
    assert(c.mrd_fill_unacked_overlap == before.mrd_fill_unacked_overlap);
}

static void test_release_xstore_states() {
    WindowCounters c;
    assert(c.cache.size() == 16);
    assert(c.sample({9, 8, 1, 2, false, false, false, false}));
    assert(c.sample({9, 9, 1, 3, false, false, false, false}));
    assert(c.total == 2 && c.cache[8] == 1 && c.cache[9] == 1);
    assert(sum(c.cache) == c.total);

    const WindowCounters before = c;
    assert(!c.sample({9, 16, 1, 4, true, false, true, false}));
    assert(c.total == before.total && c.dispatched == before.dispatched);
    assert(c.core == before.core && c.cache == before.cache);
    assert(c.fpu == before.fpu && c.fpu_op_busy == before.fpu_op_busy);
    assert(c.bg_samples == before.bg_samples);
    assert(c.blocking_decode == before.blocking_decode);
    assert(c.go_samples == before.go_samples);
    assert(c.mrd_fill_overlap == before.mrd_fill_overlap);
    assert(c.mrd_fill_unacked_overlap == before.mrd_fill_unacked_overlap);
}

static void test_reset() {
    WindowCounters c;
    assert(c.sample({160, 4, 31, 127, true, false, true, false}));
    c.reset();
    assert(c.total == 0 && c.dispatched == 0);
    assert(sum(c.core) == 0 && sum(c.cache) == 0 && sum(c.fpu) == 0);
    assert(sum(c.fpu_op_busy) == 0);
    assert(c.bg_samples == 0 && c.blocking_decode == 0 && c.go_samples == 0);
    assert(c.mrd_fill_overlap == 0 && c.mrd_fill_unacked_overlap == 0);
}

int main() {
    test_samples_and_overlaps();
    test_release_xstore_states();
    test_invalid_samples_are_atomic();
    test_reset();
    return 0;
}
