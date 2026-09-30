#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/build"
g++ -std=c++17 -Wall -Wextra -Werror -pedantic -O2 -I "$here" \
  "$here/test_old_counter_rejects.cpp" -o "$here/build/test_old_counter_rejects"
"$here/build/test_old_counter_rejects"
printf '%s\n' 'PASS old eight-bin counter rejects legal release states 8 and 9' | tee "$here/build/old_counter.log"
g++ -std=c++17 -Wall -Wextra -Werror -pedantic -O2 -I "$here" \
  "$here/window_counters_test.cpp" -o "$here/build/window_counters_test"
"$here/build/window_counters_test"
printf '%s\n' 'PASS corrected counter accepts states 8/9, sums bins, rejects 16 atomically' | tee "$here/build/window_counters.log"
g++ -std=c++17 -Wall -Wextra -Werror -pedantic -O2 -I "$here" \
  "$here/test_timed_profile.cpp" -o "$here/build/test_timed_profile"
"$here/build/test_timed_profile" "$here/build/test_timed_profile.tsv" | tee "$here/build/timed_profile.log"
python3 "$here/check_timed_profile.py" --self-test | tee "$here/build/validator_selftest.log"
python3 "$here/test_validator_capacity.py" | tee "$here/build/validator_capacity.log"
python3 "$here/test_cache_state_labels.py" | tee "$here/build/cache_state_labels.log"
