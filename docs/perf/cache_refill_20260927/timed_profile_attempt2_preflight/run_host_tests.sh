#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
resource="${1:-/home/alans/mister/MacQuadra800_fixtures/Speedometer 4.02.rsrc}"
mkdir -p "$here/build"
python3 "$here/test_resource_markers.py" "$resource" | tee "$here/build/static_markers.log"
g++ -std=c++17 -Wall -Wextra -pedantic -O2 -I "$here" \
  "$here/test_observer_original.cpp" -o "$here/build/test_observer_original"
"$here/build/test_observer_original" > "$here/build/original_observer.log"
g++ -std=c++17 -Wall -Wextra -pedantic -O2 -I "$here" \
  "$here/test_fpu_windows.cpp" -o "$here/build/test_fpu_windows"
"$here/build/test_fpu_windows" "$resource" | tee "$here/build/fpu_windows.log"
g++ -std=c++17 -Wall -Wextra -Werror -pedantic -O2 -I "$here" \
  "$here/test_timed_profile.cpp" -o "$here/build/test_timed_profile"
"$here/build/test_timed_profile" "$here/build/test_timed_profile.tsv" | tee "$here/build/timed_profile.log"
tail -1 "$here/build/original_observer.log"
