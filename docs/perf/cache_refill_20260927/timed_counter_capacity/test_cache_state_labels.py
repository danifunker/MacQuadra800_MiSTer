#!/usr/bin/env python3
from cache_state_labels import labels
states = labels()
assert states[8] == "C_XSTORE_LOOK"
assert states[9] == "C_XSTORE_WRITE"
assert states[4] == "C_FILL"
print("PASS pinned cache labels include comma-declared C_XSTORE_LOOK=8 and C_XSTORE_WRITE=9")
