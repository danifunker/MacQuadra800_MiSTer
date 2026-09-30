# Running-source provenance

The complete launch reconstruction was made in the ignored scratch directory
`scratch/fpu_timed_profile_20260927/running_source/`. That directory contained
the 130 manifest-listed inputs, the reconstructed build tree, and the original
`reconstruct.py`. It is not this documentation archive. The compact archive
here intentionally contains only selected source files in `source/`, the exact
130-entry prelaunch manifest, and the verification log; it does not contain the
full RTL/build inputs, executable, ROM, or writable disk image.

The archived `source/reconstruct.py` is a verbatim copy of the scratch script.
It expects the original reconstruction layout and is included to document the
process, not as a standalone script that can rebuild from this compact archive.
The complete source manifest is `source_manifest.sha256`; it has the recorded
prelaunch SHA-256
`7fa63eec2603a26bf99b7378643a2a8c72302228baa6d96150efec1440f07233`.
`manifest_check.log` preserves the 130-file verification from the original
reconstruction directory.

The six files under `source/` are exact copies recovered from that directory.
The three instrumentation headers and `adapter.inc` are launch inputs listed
in the 130-entry manifest; `integrate.py` and `reconstruct.py` are scratch
reproduction helpers and are not manifest inputs. `SHA256SUMS.txt` verifies
all six archive copies. `late_diagnostic.diff` documents the only
post-launch source change: the observer's prefix-abort diagnostic condition
changed from `fpu_prefix_ && !fpu_identified_` to `fpu_prefix_`. It did not
change window detection or guest/RTL behavior. The original running executable
was saved and verified by the root process observer at SHA-256
`5456932292677dddddc2e0563927e15dc54aa93e2f3ffaaf6dc3ac519dd7b188`; that
binary is intentionally omitted from this archive. The original run used the
golden disk at SHA-256
`80d8479430a66edae161c2bac6a9563dbb4f6bd0f564ee7849a555c447df8888`.

The run's RTL baseline was commit
`6456c62b4f2ef076929ce19c2c3ceee1fa7278a3`; the opt-in RAM line model was
commit `4ae2deeae531361ca3abaee4b11655be0aa03107`, the refill profiler was
`b18fd07b58a9c0dfa64c73167fe1ed58f2c58558`, and the Makefile dependency fix
was `49cf79fd4b63e22d1bdb4840ebcbe8093a9f9ffa`. The archived observer files
were scratch-only host instrumentation integrated over the pinned simulator
source; they do not alter production RTL.
