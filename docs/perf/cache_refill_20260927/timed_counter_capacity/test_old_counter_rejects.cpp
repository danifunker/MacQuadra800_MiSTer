#include "reference/window_counters_v1.h"
#include <cassert>
int main() {
    WindowCounters old;
    assert(old.cache.size() == 8);
    assert(!old.sample({9, 8, 1, 2, false, false, false, false}));
    assert(!old.sample({9, 9, 1, 3, false, false, false, false}));
    assert(old.total == 0);
}
