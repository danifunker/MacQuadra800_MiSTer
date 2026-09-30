derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# ----------------------------------------------------------------------------
# Pixel-clock domain (pll_video) — declare it asynchronous to everything else.
# ----------------------------------------------------------------------------
# The DAFB scanout runs on clk_vid (rtl/pll_video.v, 25.175 MHz for the 13"
# monitor; the 12" 512x384 option retargets the same output to 15.664 MHz at
# runtime through sys/pll_cfg, which is SLOWER than the static 25.175 MHz
# constraint derived here, so STA covers both rates). sys_top.sdc
# decouples every clock domain with set_clock_groups, but its core-PLL pattern
# matches only the MAIN pll, so a second PLL lands in NO group and every
# framework path touching CLK_VIDEO (ascal video-in, OSD, HDMI transfer) gets
# timed against unrelated domains — design-wide false violations. MacLC hit
# exactly this (MacLC.sdc:78) and the fix is the same as pll_hdmi/pll_audio.
#
# The deliberate clk_sys <-> clk_vid crossings this blesses are safe by
# construction: (a) dual-clock M10Ks (the VRAM read port in MacQuadra800.sv — no
# timed cross-port arc), (b) 2FF *_meta synchronizers (fb_base/stride/mode into
# the scanout, the video-domain reset, and the VBL toggle back into clk_sys),
# and (c) vid_stride into the VRAM address mapper, which BOTH ports have to
# agree on, so it stays a clk_sys signal read combinationally by the clk_vid
# port -- quasi-static, and a change means the guest is redrawing anyway.
set_clock_groups -asynchronous -group [get_clocks {emu|pllv|*|divclk}]

# Belt and braces: the synchronizer heads (redundant with the group above).
set_false_path -to [get_keepers {*fb_base_meta* *stride_meta* *mode_meta*}]
set_false_path -to [get_keepers {*vidrst_meta* *vbl_meta* *mon_meta*}]
