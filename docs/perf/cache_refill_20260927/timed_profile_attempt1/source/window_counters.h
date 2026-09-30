#ifndef FPU_TIMED_PROFILE_WINDOW_COUNTERS_H
#define FPU_TIMED_PROFILE_WINDOW_COUNTERS_H

#include <array>
#include <cstdint>

// Counts post-eval rising-edge samples. The overlap counters below are
// independent predicates, not transaction counts or disjoint stall causes.
struct WindowSample {
    std::uint8_t core_state = 0;
    std::uint8_t cache_state = 0;
    std::uint8_t fpu_state = 0;
    std::uint8_t fpu_op = 0;
    bool fpu_bg = false;
    bool fpu_done = false;
    bool dispatch = false;
    bool fill_acked = false;
};

struct WindowCounters {
    std::uint64_t total = 0;
    std::uint64_t dispatched = 0;
    std::array<std::uint64_t, 256> core{};
    std::array<std::uint64_t, 8> cache{};
    std::array<std::uint64_t, 32> fpu{};
    std::array<std::uint64_t, 128> fpu_op_busy{};
    std::uint64_t bg_samples = 0;
    std::uint64_t blocking_decode = 0;
    std::uint64_t go_samples = 0;
    std::uint64_t mrd_fill_overlap = 0;
    std::uint64_t mrd_fill_unacked_overlap = 0;

    void reset() noexcept {
        total = 0;
        dispatched = 0;
        core.fill(0);
        cache.fill(0);
        fpu.fill(0);
        fpu_op_busy.fill(0);
        bg_samples = 0;
        blocking_decode = 0;
        go_samples = 0;
        mrd_fill_overlap = 0;
        mrd_fill_unacked_overlap = 0;
    }

    // Reject malformed cache/FPU/op indices atomically, without changing any
    // counter. Core state is an 8-bit index and therefore always fits [256].
    bool sample(const WindowSample& s) noexcept {
        if (s.cache_state >= cache.size() || s.fpu_state >= fpu.size() ||
            s.fpu_op >= fpu_op_busy.size()) {
            return false;
        }

        ++total;
        ++core[s.core_state];
        ++cache[s.cache_state];
        ++fpu[s.fpu_state];
        if (s.dispatch) ++dispatched;
        if (s.fpu_state != 0) ++fpu_op_busy[s.fpu_op];
        if (s.fpu_bg) ++bg_samples;
        if (s.core_state == 153 && s.fpu_bg && !s.fpu_done)
            ++blocking_decode;
        if (s.core_state == 160) ++go_samples;
        if (s.core_state == 9 && s.cache_state == 4) {
            ++mrd_fill_overlap;
            if (!s.fill_acked) ++mrd_fill_unacked_overlap;
        }
        return true;
    }
};

#endif
