# Seed 27 candidate full compile

The isolated seed-27 project completed Quartus full compile on 2026-09-27. Fitter routing and TimeQuest passed; the run produced an RBF and SOF. This result is for analysis only and was not deployed.

- Device: Cyclone V 5CSEBA6U23I7; Quartus Prime 17.0.2.
- Fitter: 38,750 / 41,910 ALMs (92%), 24,642 registers, 468 / 553 M10K blocks (85%), 3,389,411 block-memory bits, 36 DSP blocks, 4 PLLs.
- Fitter RAM summary: 98 instances (69 AUTO mapped to 104 M10Ks, 17 explicit M10K instances using 364 M10Ks, 12 MLAB instances using 461 MLAB cells). Total: 468 M10Ks.
- Setup slack: CPU +0.743 ns; SDRAM +0.576 ns; HDMI +0.269 ns; HPS user clock +2.447 ns. Worst reported slack is hold +0.212 ns; every reported setup and hold TNS is 0.
- Cross-domain: sys→RAM +1.818 ns; RAM→sys +0.743 ns. See the tagged reports under `tree/scratch/`.
- RBF SHA-256: `cc948b77d304b42b27d530030e81dec10f5f880c828f8d17088d94a0e03f2185`.

The identical FPU candidate at seed 21 failed routing, with 38,659 ALMs and no RBF or STA result. The 91-ALM difference is across placements and is not an RTL area delta.

Full process/report identities and per-clock slack tables are in `full_compile_identity.json`; source and inputs are frozen by `preparation_manifest.sha256` and `tracked_source_manifest.sha256`.
