# Optional RAM retained-line model

`sim.v` leaves the original beat-port model in use by default. Add
`+ram_line_model` to enable a simulation-only 16-byte retained RAM line. Its
timing is abstract and should be used in matched baseline/candidate runs; it
does not model SDRAM rows, refresh, arbitration or the DDR clock.

| Plusarg | Default | Meaning |
| --- | ---: | --- |
| `+ram_line_model` | off | Enable RAM `mem_line_valid/tag/data` and `mem_line_pending/tag` sidebands. |
| `+ram_first_latency=N` | 1 | Rising edges from accepting a RAM beat request through asserting `mem_ack_r`, inclusive; minimum 1. Applies to RAM reads. |
| `+ram_line_publish_delay=N` | 0 | Additional rising edges after `mem_ack_r` before the complete retained line becomes valid; minimum 0. |

The model accepts a RAM read while `mem_req` is held high, asserts pending
with its physical line tag, acknowledges the requested longword after the
configured first-read latency, then publishes four words together after the
configured delay. It will not accept another beat request until the old
request drops and pending publication finishes. The platform protocol
requires a low `mem_req` interval between requests. Beat-port and posted RAM
writes invalidate the line; a posted write during a pending read prevents
publication while allowing that read to acknowledge. Reset clears the line.
ROM keeps its existing retained-line behavior. The model announces its
configuration in stdout as `[RAM-LINE-MODEL]` when enabled.

Run the directed tests with `tests/run_sim_ram_line.sh` from this directory
(or with its absolute path). The script uses Verilator 5, builds a full `emu`
testbench, and runs both default-off and enabled modes. Set `MCQ_VERILATOR5`
to another Verilator 5 binary or `MCQ_JOBS` to change build parallelism.

`tests/run_sim_ram_line.sh --calibrate` runs a controlled cache miss through
the unchanged CPU cache and machine memory service, with
`+ram_first_latency=4 +ram_line_publish_delay=2`. The measured post-edge
trace below uses cache C_FILL entry as local offset zero. The integrated
cache/SDRAM bench's warm-row trace places that entry at its cycle 2, so add
two to compare the timelines:

| Event | Model offset from C_FILL | Integrated warm-row cycle |
| --- | ---: | ---: |
| RAM model accepts request | 2 | — |
| `mem_ack_r` / SDRAM acknowledge analogue | 5 | 7 |
| Platform `bus_miss_ack` | 6 | 8 |
| Retained line valid; critical requester released | 7 | 9 |
| Cache enters C_TAGW | 10 | 12 |

The controlled trace verifies these edge positions for one RAM data miss.
They are a calibration point for the warm-row path, not a claim that this
model reproduces every physical SDRAM latency. Keep the plusargs and trace
results with each measurement manifest.
