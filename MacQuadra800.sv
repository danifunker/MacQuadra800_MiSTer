//============================================================================
//  MacQuadra800 — MiSTer top for the Quadra 800 machine.
//
//  Platform memory contract (see rtl/quadra800.sv and verilator/sim.v):
//  one ack-based beat port with mem_memsel (0 RAM, 1 ROM, 2 VRAM) plus a
//  registered 1-cycle video scanout port.  Here:
//   - RAM (32 MB) and ROM (1 MB) live in DDR3 behind a simple bridge —
//     the machine's bus FSM already tolerates wait states and the 68040
//     caches absorb the latency.  ROM writes are acked and discarded
//     (djMEMC behavior), which also write-protects the ROM region.
//   - VRAM is on-chip BRAM, 320 KB physical, advertised as 512 KB: the
//     driver's 1024-byte row pitch is compacted to the 640 bytes each
//     row can actually show, so every row of every depth is backed
//     exactly once — see the VRAM section.  The DAFB scanout expects
//     registered 1-cycle reads.  Still the main BRAM consumer.
//   - The ROM uploads as boot.rom (ioctl index 0) into the DDR3 ROM
//     region; the machine is held in reset until it lands.
//   - The SCSI disk is hps_io block device 0 (mount a .hda in the OSD);
//     the 53C96 speaks the 16-bit sd_buff interface natively.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// USER_OUT is driven by the mt32pi instance (user-port MIDI + I2C); unused
// user-port pins are held at '1 inside sys/mt32pi.sv.  UART_TXD/RTS/DTR are
// driven from the SCC further down.

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;                        // ASC samples are signed
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];
// VIDEO_ARX/ARY and VGA_DE come from the framework's video_freak below
// (aspect ratio plus the OSD's integer-scaling choice, status[13:12]).

`include "build_id.v"
localparam CONF_STR = {
	// UART token: 57600/115200 for MidiLink + PPP, plus MIDI (31250).  The SCC
	// reaches 31250 through its own WR11/TRxC path (rtl/scc.v); the token is
	// what makes the Main offer the MIDI mode, and the mode it reports back in
	// uart_mode is what gates the user-port MIDI-in merge on serialIn below.
	"MacQuadra800;UART57600:115200,MIDI;",
	// SC0, not S0: the letter after S is a flag, and 'C' is what sets
	// store_name in the Main's option parser -- i.e. what makes MiSTer write
	// config/MacQuadra800.s0 and re-mount the image on the next core start. With a
	// plain S0 the mount works but is forgotten every boot, so the disk had to
	// be picked from the OSD by hand each time and the deploy's slot-0 seed was
	// inert. Every sibling Mac core (MacLC, MacLCII, MacIIvi, MacPlus,
	// LBMacTwo) uses SC0 for this reason.
	"SC0,HDAVHD,Mount SCSI disk 0;",
	"SC1,HDAVHD,Mount SCSI disk 1;",
	// slot 4 is the CD-ROM (SCSI ID 3).  CUE/BIN/CHD need the Main fork's
	// Mac CD layer (support/mac/mac_cdrom.cpp), which serves them as a flat
	// 2048-byte-sector disc plus a TOC blob; ISO/TOAST work on a stock Main.
	"SC4,ISOTO*CUEBINCHD,Mount CD-ROM;",
	"-;",
	"O[4:3],RAM (on reset),32MB,64MB,128MB;",
	// The monitor on the DA-15.  The ROM samples the DAFB sense lines once
	// at boot and QuickDraw lays out for that geometry, so this is latched
	// under reset like the RAM size (MacLC does the same).
`ifndef VIDEO_512_OFF
	"O[5],Monitor (on reset),13in 640x480,12in 512x384;",
`endif
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[13:12],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	// Built-in Ethernet (rtl/sonic_mbx.sv + the Main fork's support/mac).  Off by
	// default: the machine is then bit for bit the one without it.  The core reads
	// only [6]; the interface choice is the Main's.  The guest's MAC is 08:00:07 +
	// the last three octets of the MiSTer's own, so there is nothing else to set.
`ifndef ETHERNET_OFF
	"-;",
	"O[6],Ethernet (on reset),Off,On;",
	"O[8:7],Net interface,eth0,eth1,wlan0,tap0;",
`endif
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"-;",
	"P1,MT32-pi;",
	"P1-;",
	"P1O[35],Use MT32-pi,Yes,No;",
	"P1O[36],Synth,Munt,FluidSynth;",
	"P1O[38:37],Munt ROM,MT-32 v1,MT-32 v2,CM-32L;",
	"P1O[41:39],SoundFont,0,1,2,3,4,5,6,7;",
	"P1O[43:42],Show Info,No,Yes,LCD-On,LCD-Auto;",
	// "Show Info = Yes" popup strings, indexed 1-based by mt32_info_disp
	"I,",
	"MT32-pi: SoundFont #0,",
	"MT32-pi: SoundFont #1,",
	"MT32-pi: SoundFont #2,",
	"MT32-pi: SoundFont #3,",
	"MT32-pi: SoundFont #4,",
	"MT32-pi: SoundFont #5,",
	"MT32-pi: SoundFont #6,",
	"MT32-pi: SoundFont #7,",
	"MT32-pi: MT-32 v1,",
	"MT32-pi: MT-32 v2,",
	"MT32-pi: CM-32L,",
	"MT32-pi: Unknown mode;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
reg         ioctl_wait;

// hps_io virtual drives.  The slot numbers follow the Main fork's Mac SCSI
// family layout (support/mac/mac.cpp) so its Toolbox / CD handlers apply:
//   0 SCSI disk 0   1 SCSI disk 1   2 (unused; PRAM in MacLC)
//   3 BlueSCSI Toolbox control   4 CD-ROM image   5 CD changer control
localparam VDNUM      = 6;
localparam VD_DISK0   = 0, VD_DISK1 = 1, VD_TOOLBOX = 3, VD_CDROM = 4, VD_CDTB = 5;
wire [31:0] sd_lba[VDNUM];
wire  [VDNUM-1:0] sd_rd, sd_wr;
wire  [VDNUM-1:0] sd_ack;
wire [12:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din[VDNUM];
wire        sd_buff_wr;
wire [32:0] TIMESTAMP;                     // Unix seconds from the HPS, for the RTC
wire  [VDNUM-1:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

// ncr53c96's three targets map onto slots 0, 1 and 4
wire [31:0] scsi_lba;
wire  [2:0] scsi_rd, scsi_wr;
wire [15:0] scsi_buff_din;
wire  [5:0] scsi_blk_cnt;               // blocks - 1 of the machine's current transaction (one at a time)
assign sd_lba[VD_DISK0] = scsi_lba;  assign sd_lba[VD_DISK1] = scsi_lba;  assign sd_lba[VD_CDROM] = scsi_lba;
// Per-slot assigns, not a concatenation: a packed literal put the CD strobe
// at bit 5 (the CD-changer control slot) once, so every CD read -- the TOC
// fetch on mount, the ROM's block 0 -- was answered on slot 5 while the core
// waited on slot 4, and the machine hung with io_busy stuck (2026-09-03).
assign sd_rd[VD_DISK0]   = scsi_rd[0];
assign sd_rd[VD_DISK1]   = scsi_rd[1];
assign sd_rd[VD_CDROM]   = scsi_rd[2];
assign sd_rd[2]          = 1'b0;
assign sd_rd[VD_TOOLBOX] = 1'b0;
assign sd_rd[VD_CDTB]    = 1'b0;
assign sd_wr[VD_DISK0]   = scsi_wr[0];
assign sd_wr[VD_DISK1]   = scsi_wr[1];
assign sd_wr[2]          = 1'b0;
assign sd_wr[VD_TOOLBOX] = 1'b0;
assign sd_wr[VD_CDROM]   = scsi_wr[2];                            // only the command block (LBA $7D......) is ever written
assign sd_wr[VD_CDTB]    = 1'b0;
assign sd_buff_din[VD_DISK0] = scsi_buff_din;
assign sd_buff_din[VD_DISK1] = scsi_buff_din;
assign sd_buff_din[VD_CDROM] = scsi_buff_din;
assign sd_lba[2] = 0; assign sd_lba[VD_TOOLBOX] = 0; assign sd_lba[VD_CDTB] = 0;
assign sd_buff_din[2] = 0; assign sd_buff_din[VD_TOOLBOX] = 0; assign sd_buff_din[VD_CDTB] = 0;
wire  [2:0] scsi_ack = {sd_ack[VD_CDROM], sd_ack[VD_DISK1], sd_ack[VD_DISK0]};

hps_io #(.CONF_STR(CONF_STR), .WIDE(1), .VDNUM(VDNUM), .BLKSZ(2)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),

	// MT32-pi "Show Info = Yes" OSD popup (CONF_STR "I," strings, 1-based)
	.info_req(mt32_info_req),
	.info({4'd0, mt32_info_disp}),

	// OSD "UART mode" as the Main reports it: 0=None, 1=PPP (the Main maps
	// its modem modes to 1 before sending), 2=Console, 3=MIDI.  Gates the
	// user-port MIDI-in merge at the serialIn assign above.
	.uart_mode(uart_mode),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.TIMESTAMP(TIMESTAMP),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.sd_lba(sd_lba),
	.sd_blk_cnt('{scsi_blk_cnt, scsi_blk_cnt, 6'd0, 6'd0, scsi_blk_cnt, 6'd0}),   // the machine's three slots; the rest never transfer
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire clk_ram;                              // 99 MHz = 3x clk_sys, SDRAM domain
wire pll_locked;

// Dedicated dot clock for the DAFB scanout.  The video used to run on clk_sys,
// which made 640x480 in an 800x525 frame refresh at 78.6 Hz with a 33 MHz dot
// clock -- far enough off spec that Main_MiSTer's vsync_adjust synthesised a
// broken HDMI mode from it (the reported screen showing the frame four times
// across the width).  25.175 MHz gives exactly VGA 640x480 @ 59.94 Hz, which
// is what the Mac LC core does; see rtl/pll_video.v.
//
// The 12" RGB monitor wants 15.664 MHz for its 640x407 frame.  That is a
// runtime RECONFIG of the one output counter (sys/pll_cfg, the ao486 /
// MacLC pattern): CLK_VIDEO has to be a raw PLL output, so a clock mux is
// not an option (Fitter Error 15836).  Only C0 changes, the VCO stays put.
// The static config is the 13" divider, so a 13" boot performs no reconfig
// at all -- MacLC's boot-time retarget glitched CLK_VIDEO while the HPS was
// mounting images and wedged the SCSI path.
wire clk_vid, pll_video_locked;
wire [63:0] reconfig_to_pll, reconfig_from_pll;
pll_video pllv
(
	.refclk(CLK_50M),
	.rst(1'b0),
	.outclk_0(clk_vid),
	.locked(pll_video_locked),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

`ifdef VIDEO_512_OFF
// VIDEO_512_OFF=1 (qsf): no runtime PLL reconfiguration -- the 13" 640x480
// divider is the static config and stays.  Saves the pll_cfg block (~360
// ALMs), the area lever for CPU builds that keep the CD-ROM target.
assign reconfig_to_pll = 64'd0;
wire   pix_quiet = 1'b0;
wire   mon_12in  = 1'b0;
`else
wire        pixcfg_waitrequest;
reg         pixcfg_write = 0;
reg   [5:0] pixcfg_address = 0;
reg  [31:0] pixcfg_data = 0;
// The framework's trimmed reconfiguration core (sys/pll_cfg/pll_cfg_hdmi.v,
// Altera's altera_pll_reconfig_core with the unused features cut out) has
// the same management interface and the MODE / C-counter / START registers
// this path writes, at ~300 logic cells instead of the generic IP's 715.
pll_cfg_hdmi pll_video_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(pixcfg_waitrequest),
	.mgmt_write(pixcfg_write),
	.mgmt_address(pixcfg_address),
	.mgmt_writedata(pixcfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// C0 counter word per monitor: {[22:18] counter#=0, [17] odd-div, [16]
// bypass, [15:8] high count, [7:0] low count} (sys/pll_cfg/
// altera_pll_reconfig_core.v).  VCO 704.9 MHz: /28 = 25.175 MHz, /45 =
// 15.664 MHz.
// The monitor is latched under reset like the RAM size (ram_cfg below):
// the ROM reads the DAFB sense lines once at boot.
reg mon_12in = 1'b0;
always @(posedge clk_sys) if (reset) mon_12in <= status[5];
wire [31:0] pix_c0 = mon_12in ? 32'h00021716 : 32'h00000E0E;

// The retarget never drops PLL lock (the VCO is untouched), so the scanout
// would step to the new rate mid-frame and Main's vsync_adjust would
// measure one chimera frame and latch an out-of-spec HDMI mode (MacLC,
// 2026-08-08).  pix_quiet holds the video reset from retarget-pending
// until ~84 ms after the FSM has consumed it, so a monitor change presents
// as a clean blank-and-return.
reg pix_quiet = 1'b0;
always @(posedge CLK_50M) begin : pix_reconfig
	reg [21:0] settle = 22'd0;
	reg [31:0] c0_cur = 32'h00000E0E;    // = the static 13" config
	reg [31:0] c0_s1, c0_s2;
	reg [2:0]  state = 0;
	c0_s1 <= pix_c0;                     // settle across clk_sys -> CLK_50M
	c0_s2 <= c0_s1;
	if (c0_s2 == c0_s1 && c0_s2 != c0_cur) begin
		settle    <= 22'h3FFFFF;
		pix_quiet <= 1'b1;
	end else if (settle != 0) begin
		settle    <= settle - 1'd1;
	end else begin
		pix_quiet <= 1'b0;
	end
	if (!pixcfg_waitrequest) begin
		pixcfg_write <= 0;
		if (pll_video_locked) begin
			if (state) state <= state + 1'd1;
			case (state)
				0: if (c0_s2 == c0_s1 && c0_s2 != c0_cur) begin
						c0_cur <= c0_s2;
						state  <= 1;
					end
				1: begin pixcfg_address <= 0; pixcfg_data <= 0;      pixcfg_write <= 1; end // polled mode
				3: begin pixcfg_address <= 5; pixcfg_data <= c0_cur; pixcfg_write <= 1; end // C0 counter
				5: begin pixcfg_address <= 2; pixcfg_data <= 0;      pixcfg_write <= 1; end // start
				default: ;
			endcase
		end
	end
end
`endif

// video-domain reset: released only once the pixel clock is locked AND the
// machine is out of reset AND no retarget is settling, 2FF-synced into
// clk_vid (pix_quiet is a multi-ms CLK_50M level; the 2FF is its sync)
reg vidrst_meta, vidrst_s;
always @(posedge clk_vid) begin
	vidrst_meta <= reset | ~pll_video_locked | pix_quiet;
	vidrst_s    <= vidrst_meta;
end
wire nreset_vid = ~vidrst_s;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_1(clk_ram),
	.outclk_0(clk_sys),                    // 33.000000 MHz machine clock — the
	                                       // real Quadra 800 rate, and the exact
	                                       // base every time-anchored divider
	                                       // assumes (RTC SEC_DIV, the 60.15 Hz
	                                       // tick, VIA E_HALF, ASC SAMPLE_DIV)
	.locked(pll_locked)
);

// hold the machine until the PLL locks and boot.rom has landed in DDR3
wire rom_index = (ioctl_index[5:0] == 0);
reg  rom_loaded = 0;
reg  dl_d = 0;
always @(posedge clk_sys) begin
	dl_d <= ioctl_download;
	if (dl_d && !ioctl_download && rom_index) rom_loaded <= 1;
end

wire reset = RESET | status[0] | buttons[1] | ioctl_download |
             ~rom_loaded | ~pll_locked;

// Re-announce the mounted image to the machine after EVERY reset.
//
// ncr53c96 latches `mounted`/`disk_blocks` only on the img_mounted pulse, and
// its always block is reset-gated, so a machine reset throws the mount away.
// The Main sends that pulse exactly twice in a core's life -- once at core
// start (SC0 restoring the saved mount) and again if you pick a file in the
// OSD -- so after any reset the target believed no disk was present and the ROM
// dropped to the flashing-? screen. That is why the disk had to be re-assigned
// by hand after every reboot.
//
// Two distinct problems are handled here:
//   1. The core-start mount lands INSIDE the reset window, because `reset`
//      spans the whole boot.rom ioctl upload -- so the pulse would be dropped
//      even on the first boot. Symptom: the Main holds the file open (fd
//      present, pos stuck at 0) while the machine shows flashing-?.
//   2. Every LATER reset clears the target's copy with no new pulse coming.
//
// So the mount is remembered here, outside the machine reset, and replayed on
// each reset release as well as when it first arrives. Size is captured a cycle
// ahead of the pulse so it is stable when the target samples it.
// Three targets, one memory each.  A Main pulse for slot 0/1/4 records the
// size and schedules a replay; a reset release schedules a replay of every
// remembered slot.  Replays go out one target per clock pair so the machine
// sees a single pulse with its own size each time.
reg  [2:0] mount_valid  = 0;      // an image is mounted (survives machine reset)
reg [63:0] mount_size [0:2];
reg  [2:0] mount_replay = 0;
reg        reset_d      = 1;
reg  [2:0] mach_img_mounted = 0;
reg [63:0] mach_img_size = 0;
wire [2:0] main_mount = {img_mounted[VD_CDROM], img_mounted[VD_DISK1], img_mounted[VD_DISK0]};
integer mi;
always @(posedge clk_sys) begin
	mach_img_mounted <= 0;
	reset_d          <= reset;

	for (mi = 0; mi < 3; mi = mi + 1)
		if (main_mount[mi]) begin
			mount_size[mi]   <= img_size;
			mount_valid[mi]  <= (img_size != 0);   // size 0 = eject, replay that too
			mount_replay[mi] <= 1;
		end
	if (reset_d && !reset) mount_replay <= mount_replay | mount_valid;   // reset just released

	if (!reset && mach_img_mounted == 3'b000) begin
		if (mount_replay[0]) begin
			mount_replay[0] <= 0; mach_img_size <= mount_size[0]; mach_img_mounted <= 3'b001;
		end
		else if (mount_replay[1]) begin
			mount_replay[1] <= 0; mach_img_size <= mount_size[1]; mach_img_mounted <= 3'b010;
		end
		else if (mount_replay[2]) begin
			mount_replay[2] <= 0; mach_img_size <= mount_size[2]; mach_img_mounted <= 3'b100;
		end
	end
end

///////////////////////   MACHINE   //////////////////////////////

wire        mem_req, mem_write;
wire [31:2] mem_addr;
wire  [3:0] mem_be;
wire [31:0] mem_wdata;
wire  [1:0] mem_memsel;
wire [31:0] mem_rdata;                     // VRAM/ROM reg, or the SDRAM bridge
wire        mem_ack;
wire        mem_vram_wp;                   // direct VRAM write (mem_req low)
reg  [31:0] mem_rdata_r;
reg         mem_ack_r;

wire        mem_is_ram  = (mem_memsel == 2'd0);
wire        mem_is_rom  = (mem_memsel == 2'd1);
wire        mem_is_vram = !mem_is_ram && !mem_is_rom;

wire [21:2] vid_addr;
reg  [31:0] vid_rdata;
wire [13:0] vid_stride;

wire [255:0] m_debug_status;
wire [127:0] m_debug_status2;

localparam RAM_ADDR_BITS = 27;             // address ceiling: 128 MB

// Installed RAM from the OSD (0=32MB, 1=64MB, 2=128MB — powers of two only;
// see the ram_limit comment in rtl/quadra800.sv for why 48MB needs the djMEMC
// bank decode first).
wire [1:0] ram_cfg_osd = (status[4:3] == 2'd3) ? 2'd0 : status[4:3];

// Sampled ONLY while the machine is in reset, so a new size takes effect at the
// next reset and never under a running machine.
//
// This used to fold ram_cfg_change straight into `reset`, which meant nudging
// the OSD setting instantly hard-reset a running Mac OS -- a power-cut on a
// mounted HFS volume, and a good way to corrupt the disk by accident. The ROM
// sizes memory exactly once during startup, so applying a change live could
// never have worked anyway: the machine would keep using the size it probed.
reg [1:0] ram_cfg = 2'd0;
always @(posedge clk_sys) if (reset) ram_cfg <= ram_cfg_osd;

wire        sdr_line_valid;
wire        sdr_wq_room;
wire        mem_wp_valid;
wire [31:2] mem_wp_addr;
wire  [3:0] mem_wp_be;
wire [31:0] mem_wp_data;
wire [26:4] sdr_line_tag;
wire [127:0] sdr_line_data;
wire        sdr_line_pending;
wire [26:4] sdr_line_pending_tag;

// The CD-ROM target and its audio engine cost ~2,800 ALMs.  A build that
// needs them back (CPU work) adds to the qsf:
//   set_global_assignment -name VERILOG_MACRO "CDROM_OFF=1"
// and gets a machine with two hard disks and no ID 3; the OSD's CD line
// still exists but the mount goes nowhere.
`ifdef CDROM_OFF
localparam CDROM_EN = 0;
`else
localparam CDROM_EN = 1;
`endif

// Built-in Ethernet.  The build switch is
//   set_global_assignment -name VERILOG_MACRO "ETHERNET_OFF=1"
// (no SONIC front-end, no DMA master, no DDR3 window port, no OSD lines); the
// runtime switch is OSD [6], latched under reset like the RAM size because the
// guest must never see the chip appear or vanish under it.
`ifdef ETHERNET_OFF
localparam SONIC_EN = 0;
`else
localparam SONIC_EN = 1;
`endif
reg         eth_ena = 1'b0;
// The machine's three fast-path switches (store buffer, SDRAM line, DMA
// snoop) were OSD "Dbg" options during the Ethernet bring-up; the paths
// have been on in every release since, so the OSD lines are gone and the
// switches are tied to their normal state.
wire  [2:0] dbg_sw  = 3'd0;
always @(posedge clk_sys) if (reset) begin
	eth_ena <= (SONIC_EN != 0) && status[6];
end
wire [11:0] eth_mem_addr;
wire        eth_mem_rd, eth_mem_we;
wire [63:0] eth_mem_wdata;
reg         eth_mem_accept = 1'b0;
wire        eth_mem_rvalid;

quadra800 #(.RAM_ADDR_BITS(RAM_ADDR_BITS), .CDROM(CDROM_EN), .SONIC(SONIC_EN)) machine (
	.clk(clk_sys),
	.nreset(~reset),
	.ce(1'b1),
	.clk_vid(clk_vid),
	.nreset_vid(nreset_vid),
	.ram_cfg(ram_cfg),
	.mon_12in(mon_12in),

	.mem_req(mem_req),
	.mem_write(mem_write),
	.mem_addr(mem_addr),
	.mem_be(mem_be),
	.mem_wdata(mem_wdata),
	.mem_memsel(mem_memsel),
	.mem_rdata(mem_rdata),
	.mem_ack(mem_ack),
	.mem_wp_valid(mem_wp_valid),
	.mem_wp_addr(mem_wp_addr),
	.mem_wp_be(mem_wp_be),
	.mem_wp_data(mem_wp_data),
	.mem_wq_room(sdr_wq_room),
	.mem_vram_wp(mem_vram_wp),
	.mem_line_valid(sdr_line_valid),
	.mem_line_tag(sdr_line_tag),
	.mem_line_data(sdr_line_data),
	.mem_rom_line_valid(rom_line_valid),
	.mem_rom_line_tag(rom_line_tag),
	.mem_rom_line_data(rom_line),
	.mem_line_pending(sdr_line_pending),
	.mem_line_pending_tag(sdr_line_pending_tag),

	.vid_addr(vid_addr),
	.vid_rdata(vid_rdata),
	.vid_stride(vid_stride),
	.VGA_R(mac_vga_r),
	.VGA_G(mac_vga_g),
	.VGA_B(mac_vga_b),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_HB(m_hblank),
	.VGA_VB(m_vblank),
	.CE_PIXEL(CE_PIXEL),

	.AUDIO_L(mac_audio_l),
	.cd_snd_l(cd_snd_l),
	.cd_snd_r(cd_snd_r),
	.AUDIO_R(mac_audio_r),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.timestamp(TIMESTAMP),

	.scc_rxd_a(serialIn),
	.scc_txd_a(serialOut),
	.scc_cts_a(serialCTS),
	.scc_rts_a(serialRTS),
	.scc_rxd_b(1'b1),          // printer port RX idles high (no LocalTalk yet)
	.scc_txd_b(serialOutB),

	.img_mounted(mach_img_mounted),
	.img_size(mach_img_size),
	.io_lba(scsi_lba),
	.io_blk_cnt(scsi_blk_cnt),
	.io_rd(scsi_rd),
	.io_wr(scsi_wr),
	.io_ack(scsi_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(scsi_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.dbg_berr(),
	.dbg_berr_addr(),
	.dbg_overlay(),
	.debug_status(m_debug_status),
	.debug_status2(m_debug_status2),
	.debug_fault(),
	.debug_halted(),

	.eth_ena(eth_ena),
	.dbg_sw(dbg_sw),
	.eth_mem_addr(eth_mem_addr),
	.eth_mem_rd(eth_mem_rd),
	.eth_mem_we(eth_mem_we),
	.eth_mem_wdata(eth_mem_wdata),
	.eth_mem_accept(eth_mem_accept),
	.eth_mem_rvalid(eth_mem_rvalid),
	.eth_mem_rdata(DDRAM_DOUT)
);

wire m_hblank, m_vblank;
assign CLK_VIDEO = clk_vid;
wire mac_de = ~(m_hblank | m_vblank);

// Aspect ratio and integer scaling are the framework's: video_freak turns
// the OSD's Scale choice into the VIDEO_ARX/ARY scaled-size form the
// scaler understands (V-Integer keeps every Mac line an integer number of
// output lines).  No crop.
video_freak video_freak
(
	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(mac_de),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE({1'b0, status[13:12]})
);

//////////////////////////////////////////////////////////////////
// SCC serial — MidiLink / PPP / console on channel A, MT32-pi on the user port
//
// Channel A TX fans out to BOTH the HPS UART (UART_TXD -> MidiLink, PPP,
// console) and the MT32-pi's MIDI-in on the user port.  RX sources:
//   - ALWAYS the HPS UART (UART_RXD) — MidiLink / console / PPP.
//   - In OSD UART mode = MIDI ONLY, the user-port MIDI-in line (mt32_midi_rx:
//     the Pi's TX pin when an MT32-pi is detected, USER_IN[0] otherwise) is
//     AND-merged in.  Both lines idle high, so the merge is inert until a
//     source actually transmits and a start bit from either reaches the SCC.
//
// The uart_mode gate is load-bearing, and is the one piece here that was paid
// for in hardware debugging on the LC: an unconditional
// `mt32_available ? mt32_midi_rx : UART_RXD` mux repointed guest RX at the
// Pi's MIDI-return line whenever a Pi was detected, so EVERY guest-receive
// path died with a Pi plugged in while TX kept working (which made it look
// one-directional).  PPP was what exposed it — LCP hung because the guest
// never saw pppd's ConfAck.  Outside MIDI mode serialIn is UART_RXD alone, so
// the user port can never hijack guest receive; PPP/console are unaffected.
//////////////////////////////////////////////////////////////////
wire serialOut, serialRTS;
wire serialOutB;                           // printer port TX — unused for now
// The HPS UART's RTS, as the framework presents it (active low): a printer
// daemon or pppd opened with RTS/CTS asserts it (low) when it can take data.
// It reaches RR0's CTS bit uninverted, which is the polarity the Mac's
// drivers want (hardware-settled, docs/perf/p262_trial_hw_20260929): 0 =
// clear to send, and a daemon that is not running or drops RTS holds the
// Mac off.  It used to be a constant 1 (never reaching RR0, which read 0).
wire serialCTS = UART_CTS;
wire [7:0] uart_mode;                      // from hps_io; 3 = MIDI

wire userport_midi_in = (uart_mode == 8'd3) ? mt32_midi_rx : 1'b1;
wire serialIn = UART_RXD & userport_midi_in;
assign UART_TXD = serialOut;
assign UART_RTS = serialRTS;
assign UART_DTR = UART_DSR;

// MT32-pi on the user port (framework module sys/mt32pi.sv): serial MIDI out
// on USER_OUT[1] at the SCC's programmed rate, I2S synth audio back on
// USER_IN[2/4/5], I2C detection/control on USER_IN[0]/[3].  The synth path
// runs in the fixed 24.576 MHz CLK_AUDIO domain; the LCD-overlay raster
// tracker runs on clk_vid and its box is composited into VGA_R/G/B below.
wire [15:0] mt32_i2s_l, mt32_i2s_r;
wire        mt32_available;
wire        mt32_midi_rx;
wire        mt32_disable = status[35];              // "Use MT32-pi" = No
wire        mt32_mute    = mt32_available & mt32_disable;
wire        mt32_use     = mt32_available & ~mt32_disable;
wire  [1:0] mt32_info    = status[43:42];           // No/Yes/LCD-On/LCD-Auto
wire  [7:0] mt32_mode, mt32_rom, mt32_sf;
wire        mt32_newmode;
wire        mt32_lcd_en, mt32_lcd_pix, mt32_lcd_update;

mt32pi mt32pi
(
	.CLK_AUDIO(CLK_AUDIO),
	.CLK_VIDEO(clk_vid),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.USER_IN(USER_IN),
	.USER_OUT(USER_OUT),
	.reset(reset),
	.midi_tx(serialOut | mt32_mute),        // idle the Pi's MIDI-in when off
	.midi_rx(mt32_midi_rx),
	.mt32_i2s_r(mt32_i2s_r),
	.mt32_i2s_l(mt32_i2s_l),
	.mt32_available(mt32_available),
	.mt32_mode_req(status[36]),             // Synth: 0=Munt, 1=FluidSynth
	.mt32_rom_req(status[38:37]),           // Munt ROM: MT-32 v1/v2/CM-32L
	.mt32_sf_req({5'd0, status[41:39]}),    // SoundFont 0-7
	.mt32_mode(mt32_mode),
	.mt32_rom(mt32_rom),
	.mt32_sf(mt32_sf),
	.mt32_newmode(mt32_newmode),
	.mt32_lcd_en(mt32_lcd_en),
	.mt32_lcd_pix(mt32_lcd_pix),
	.mt32_lcd_update(mt32_lcd_update)
);

// "Show Info = Yes": on a Pi-acknowledged mode change (mt32_newmode toggles),
// flash the mode name via the framework info popup (hps_io info_req/info ->
// the CONF_STR "I," strings, 1-based).  Block is ao486-verbatim.
reg       mt32_info_req;
reg [3:0] mt32_info_disp;
always @(posedge clk_sys) begin
	reg old_mode;

	old_mode <= mt32_newmode;
	mt32_info_req <= (old_mode ^ mt32_newmode) && (mt32_info == 1);

	mt32_info_disp <= (mt32_mode == 'hA2) ? (4'd1 + mt32_sf[2:0]) :
	                  (mt32_mode == 'hA1 && mt32_rom == 0) ?  4'd9 :
	                  (mt32_mode == 'hA1 && mt32_rom == 1) ?  4'd10 :
	                  (mt32_mode == 'hA1 && mt32_rom == 2) ?  4'd11 : 4'd12;
end

// LCD overlay visibility (ao486 pattern): "LCD-On" pins it up, "LCD-Auto"
// shows it while the Pi pushes LCD updates and drops it after a timeout.
// clk_vid is the 25.175 MHz dot clock here, so 50M ticks is ~2.0 s.
reg mt32_lcd_on;
always @(posedge clk_vid) begin
	int to;
	reg old_update;

	old_update <= mt32_lcd_update;
	if(to) to <= to - 1;

	if(mt32_info == 2) mt32_lcd_on <= 1;
	else if(mt32_info != 3) mt32_lcd_on <= 0;
	else begin
		if(!to) mt32_lcd_on <= 0;
		if(old_update ^ mt32_lcd_update) begin
			mt32_lcd_on <= 1;
			to <= 50_000_000;
		end
	end
end

// Video: inside the overlay box the picture is dimmed to its low 6 bits and
// the LCD text pixel is OR'd into the top 2 (ao486's compositing, verbatim).
wire [7:0] mac_vga_r, mac_vga_g, mac_vga_b;
wire       mt32_lcd = mt32_lcd_en & mt32_lcd_on;
assign VGA_R = mt32_lcd ? {{2{mt32_lcd_pix}}, mac_vga_r[7:2]} : mac_vga_r;
assign VGA_G = mt32_lcd ? {{2{mt32_lcd_pix}}, mac_vga_g[7:2]} : mac_vga_g;
assign VGA_B = mt32_lcd ? {{2{mt32_lcd_pix}}, mac_vga_b[7:2]} : mac_vga_b;

// Audio: the MT32-pi I2S return joins at unity gain, gated by mt32_use (a Pi
// is present AND "Use MT32-pi" is Yes); exact zeros otherwise, so the mix is
// bit-identical to today with no Pi attached or the device disabled.
wire signed [15:0] mac_audio_l, mac_audio_r;
// CD-DA from the SCSI CD-ROM's audio engine (rtl/cd_audio.sv): exact zeros
// unless the AppleCD player is playing, so the mix is unchanged otherwise.
// These were left undeclared at the instantiation once (implicit 1-bit
// nets, never summed): the engine played, the core stayed silent.
wire signed [15:0] cd_snd_l, cd_snd_r;
wire signed [17:0] audio_mix_l = {{2{mac_audio_l[15]}}, mac_audio_l}
                               + {{2{cd_snd_l[15]}}, cd_snd_l}
                               + (mt32_use ? {{2{mt32_i2s_l[15]}}, mt32_i2s_l} : 18'sd0);
wire signed [17:0] audio_mix_r = {{2{mac_audio_r[15]}}, mac_audio_r}
                               + {{2{cd_snd_r[15]}}, cd_snd_r}
                               + (mt32_use ? {{2{mt32_i2s_r[15]}}, mt32_i2s_r} : 18'sd0);
assign AUDIO_L = (audio_mix_l > 18'sd32767)  ?  16'sd32767 :
                 (audio_mix_l < -18'sd32768) ? -16'sd32768 : audio_mix_l[15:0];
assign AUDIO_R = (audio_mix_r > 18'sd32767)  ?  16'sd32767 :
                 (audio_mix_r < -18'sd32768) ? -16'sd32768 : audio_mix_r[15:0];

assign LED_USER = ioctl_download | (|sd_rd) | (|sd_wr);
assign LED_DISK = {1'b1, (|sd_rd) | (|sd_wr)};

//////////////////////////////////////////////////////////////////
// SDRAM — the machine's RAM.  ROM stays in DDR3 (it is uploaded once
// through the ioctl path and read rarely enough that latency is free).
//
// rtl/sdram_beat32.sv owns the 16-bit controller and both clock domains:
// one read captures a complete BL8/16-byte line, returning its critical
// longword first; a write uses two 16-bit commands and is acknowledged here
// before it drains behind the machine.  The
// controller runs at 99 MHz — three times clk_sys, from the same PLL — and
// derives SDRAM_CLK itself with an altddio_out, so no phase-shifted clock
// is needed here.
//////////////////////////////////////////////////////////////////

wire        sdr_ack;
wire [31:0] sdr_rdata;

// The ack the machine sees is this bridge's, the VRAM port's or the ROM one;
// they are never asserted together, because mem_memsel picks exactly one
// consumer.  A VRAM beat is acknowledged in its second clock, straight from
// the block RAM's output (vram_ack, below).
wire        vram_ack;
reg  [31:0] vram_qa;
assign mem_ack   = mem_ack_r | sdr_ack | vram_ack;
assign mem_rdata = sdr_ack ? sdr_rdata : mem_is_vram ? vram_qa : mem_rdata_r;

sdram_beat32 sdr
(
	.init      (~pll_locked),
	.clk_sys   (clk_sys),
	.clk_ram   (clk_ram),

	.req       (mem_req && mem_is_ram),
	.we        (mem_write),
	.addr      (mem_addr[26:2]),
	.be        (mem_be),
	.wdata     (mem_wdata),
	.ack       (sdr_ack),
	.rdata     (sdr_rdata),
	.busy      (),                       // ordering is the bridge's own affair
	.line_valid_o(sdr_line_valid),
	.line_tag_o(sdr_line_tag),
	.line_data_o(sdr_line_data),
	.line_pending_o(sdr_line_pending),
	.line_pending_tag_o(sdr_line_pending_tag),
	.wp_valid  (mem_wp_valid),
	.wp_addr   (mem_wp_addr[26:2]),
	.wp_be     (mem_wp_be),
	.wp_data   (mem_wp_data),
	.wq_room   (sdr_wq_room),

	.SDRAM_DQ  (SDRAM_DQ),
	.SDRAM_A   (SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA  (SDRAM_BA),
	.SDRAM_nCS (SDRAM_nCS),
	.SDRAM_nWE (SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE (SDRAM_CKE),
	.SDRAM_CLK (SDRAM_CLK)
);

//////////////////////////////////////////////////////////////////
// VRAM — on-chip, true dual port: CPU beats on port A (2-cycle
// handshake: capture, then deliver), DAFB scanout on port B with the
// registered 1-cycle read the machine expects.
//
// The machine's 2 MB window aliases mod 512 KB, so a ROM size probe sees
// the classic power-of-2 wrap and ADVERTISES 512 KB.  Backing all of it
// is impossible on this device — but it does not have to be backed
// densely; see the compaction note on VRAM_WORDS below.
//////////////////////////////////////////////////////////////////
// STRIDE COMPACTION.  The ROM programs a 1024-byte row pitch (confirmed on
// hardware and by the sim's [DAFB] tap), so a 480-row framebuffer spans
// 0x1000 + 480*1024 = 495,616 bytes — far past anything M10K can hold, and
// the old fold aliased screen rows 304..479 back onto rows 100..275 (the
// duplicated boot floppy seen on the DE10).
//
// But at 640 pixels wide only the FIRST 640 bytes of each 1024-byte row are
// ever visible: 80 bytes at 1bpp, 160 at 2bpp, 320 at 4bpp, 640 at 8bpp.
// The remaining 384 bytes are pitch padding no supported depth reaches.  So
// store 640 bytes of every row and drop the tail: the whole 512 KB window
// becomes 512*640 = 320 KB of BRAM, which fits with room to spare, and
// EVERY row of EVERY depth (8bpp included) is backed exactly once — no
// aliasing anywhere in the visible framebuffer.
//
// The 384-byte tails all share one scratch block, so a write and read-back
// at the same tail address still agree (VRAM size probes poke row-aligned
// offsets, which are all col 0).  Only software genuinely storing data in
// the pitch padding of two different rows at once would notice.
//
// Compaction assumes the 1024-byte pitch, so it engages only when the
// driver has actually programmed one; any pitch <= 640 already fits the
// array linearly and maps identically (with the old fold as a backstop for
// probe reads past the end).
localparam VRAM_WORDS = 82016;             // 320.4 KB: 512*160 + 96 tail
localparam [16:0] VRAM_FOLD = 17'd52224;   // 204 KB, in words
localparam [16:0] VRAM_TAIL = 17'd81920;   // 512 rows * 160 words

wire vram_compact = (vid_stride == 14'd1024);

function [16:0] vram_map(input [16:0] w);  // window word -> storage word
	reg [8:0] row;                         // 1024 B = 256 words per row
	reg [7:0] col;
	begin
		row = w[16:8];
		col = w[7:0];
		if (!vram_compact)
			vram_map = (w >= VRAM_WORDS) ? (w - VRAM_FOLD) : w;
		else if (col < 8'd160)             // visible 640 bytes: row*160 + col
			vram_map = {row, 7'd0} + {2'd0, row, 5'd0} + {9'd0, col};
		else                               // pitch padding: shared scratch
			vram_map = VRAM_TAIL + {9'd0, (col - 8'd160)};
	end
endfunction

reg        vram_ph;                        // port-A phase: 0 capture, 1 deliver

wire [16:0]  va_addr     = vram_map(mem_addr[18:2]);
wire [16:0]  vb_addr     = vram_map(vid_addr[18:2]);
// a beat writes in its capture clock; a direct write (the store buffer's
// drain, quadra800 bus_vram_direct) is a one-clock pulse with mem_req low
wire         va_we       = (mem_req && mem_is_vram && mem_write && !vram_ph) || mem_vram_wp;
assign       vram_ack    = mem_req && mem_is_vram && vram_ph;

// Storage is one byte-wide array per lane rather than one 32-bit array
// with byte enables: mem_be becomes each lane's write enable, so nothing
// rests on Quartus inferring byte enables on a true-dual-port M10K, and a
// x8 two-read-port array is the simplest shape a block can take.
// no_rw_check is accurate here — port A throws its read away on a write
// cycle (vram_ph delivers on the FOLLOWING cycle), so the
// read-during-write value is a genuine don't-care.  Without these
// attributes Quartus honors the implied "old data" same-port
// read-during-write in logic cells, and 2.5 Mbit of registers is what
// turns Analysis & Synthesis into an all-day run that never finishes.
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram0 [0:VRAM_WORDS-1];
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram1 [0:VRAM_WORDS-1];
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram2 [0:VRAM_WORDS-1];
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] vram3 [0:VRAM_WORDS-1];

always @(posedge clk_sys) begin            // port A: CPU beats
	if (va_we && mem_be[0]) vram0[va_addr] <= mem_wdata[7:0];
	if (va_we && mem_be[1]) vram1[va_addr] <= mem_wdata[15:8];
	if (va_we && mem_be[2]) vram2[va_addr] <= mem_wdata[23:16];
	if (va_we && mem_be[3]) vram3[va_addr] <= mem_wdata[31:24];
	vram_qa <= {vram3[va_addr], vram2[va_addr],
	            vram1[va_addr], vram0[va_addr]};
end

// port B: DAFB scanout, on the PIXEL clock.  M10K is natively dual-clock, so
// this costs nothing and there is no timed arc between the ports -- the
// crossing is blessed in MacQuadra800.sdc along with the rest of clk_vid.
always @(posedge clk_vid)
	vid_rdata <= {vram3[vb_addr], vram2[vb_addr],
	              vram1[vb_addr], vram0[vb_addr]};

//////////////////////////////////////////////////////////////////
// DDR3 bridge — RAM + ROM regions, plus the boot.rom upload path.
// 64-bit word convention: the machine's 32-bit word at byte address A
// sits in DDRAM_DOUT[31:0] when A[2]=0 and [63:32] when A[2]=1; the
// big-endian byte packing inside the 32-bit lane is preserved, so
// mem_be maps 1:1 onto DDRAM_BE (shifted by the half-select).
//////////////////////////////////////////////////////////////////
assign DDRAM_CLK = clk_sys;

localparam [28:0] DDR_RAM_BASE = 29'h0600_0000;   // byte 0x3000_0000 >> 3
localparam [28:0] DDR_ROM_BASE = 29'h0700_0000;   // byte 0x3800_0000 >> 3
// The Ethernet mailbox window the Main fork maps (support/mac/mac_eth.h): ARM
// physical 0x1FF00000, the area the Minimig A2065 and the MacLC card use too.
localparam [28:0] DDR_ETH_BASE = 29'h03FE_0000;   // byte 0x1FF0_0000 >> 3

reg  [7:0] ddram_burstcnt;
reg [28:0] ddram_addr;
reg [63:0] ddram_din;
reg  [7:0] ddram_be;
reg        ddram_we, ddram_rd;
assign DDRAM_BURSTCNT = ddram_burstcnt;
assign DDRAM_ADDR     = ddram_addr;
assign DDRAM_DIN      = ddram_din;
assign DDRAM_BE       = ddram_be;
assign DDRAM_WE       = ddram_we;
assign DDRAM_RD       = ddram_rd;

reg        ioctl_pend;
reg [26:0] ioctl_a;
reg [15:0] ioctl_d;
reg        ddr_wait_data;                  // read issued, awaiting DOUT_READY
// The ROM's retained line: every ROM read fetches its whole 16-byte line in
// one two-beat burst, and the machine answers the line's other longwords from
// here (quadra800 bus_rom_match) -- the I-cache's fill of a ROM line is one
// DDR3 round trip instead of four.  ROM changes only by a boot.rom download.
reg [127:0] rom_line;                      // longword 0 in [127:96]
reg  [19:4] rom_line_tag;
reg         rom_line_valid = 1'b0;
reg   [1:0] ddr_rd_word;
reg         ddr_rd_beat1;                  // the line's first 64-bit beat is in
reg        ddr_wait_eth = 1'b0;            // ... for the Ethernet window instead
assign     eth_mem_rvalid = ddr_wait_eth && DDRAM_DOUT_READY;

always @(posedge clk_sys) begin
	mem_ack_r <= 0;
	eth_mem_accept <= 0;

	// boot.rom halfwords: capture, then stall hps_io until written
	if (ioctl_download && rom_index && ioctl_wr) begin
		ioctl_pend <= 1;
		ioctl_wait <= 1;
		ioctl_a <= ioctl_addr;
		ioctl_d <= ioctl_dout;
	end

	if (!DDRAM_BUSY) begin
		ddram_we <= 0;
		ddram_rd <= 0;
	end

	// VRAM beats (BRAM port A): the capture edge, then vram_qa is delivered
	// with the combinational vram_ack; the machine drops mem_req on it
	if (mem_req && mem_is_vram) vram_ph <= !vram_ph;

	if (ddr_wait_data) begin
		if (DDRAM_DOUT_READY) begin
			// beat 0 holds longwords 0 (low half) and 1, beat 1 longwords 2 and 3
			if (!ddr_rd_beat1) begin
				rom_line[127:64] <= {DDRAM_DOUT[31:0], DDRAM_DOUT[63:32]};
				ddr_rd_beat1 <= 1;
			end
			else begin
				rom_line[63:0] <= {DDRAM_DOUT[31:0], DDRAM_DOUT[63:32]};
				rom_line_valid <= 1;
				case (ddr_rd_word)
					2'd0: mem_rdata_r <= rom_line[127:96];
					2'd1: mem_rdata_r <= rom_line[95:64];
					2'd2: mem_rdata_r <= DDRAM_DOUT[31:0];
					2'd3: mem_rdata_r <= DDRAM_DOUT[63:32];
				endcase
				mem_ack_r   <= 1;
				ddr_wait_data <= 0;
			end
		end
	end
	else if (ddr_wait_eth) begin
		if (DDRAM_DOUT_READY) ddr_wait_eth <= 0;
	end
	else if (!DDRAM_BUSY && !ddram_we && !ddram_rd) begin
		if (ioctl_pend) begin
			// file bytes are big-endian in the 32-bit lane: swap the
			// little-endian ioctl halfword and replicate across lanes,
			// steering with BE
			ddram_addr     <= DDR_ROM_BASE | {10'd0, ioctl_a[19:3]};
			ddram_din      <= {4{{ioctl_d[7:0], ioctl_d[15:8]}}};
			ddram_be       <= ioctl_a[1] ? (ioctl_a[2] ? 8'h30 : 8'h03)
			                             : (ioctl_a[2] ? 8'hC0 : 8'h0C);
			ddram_burstcnt <= 8'd1;
			ddram_we       <= 1;
			ioctl_pend     <= 0;
			ioctl_wait     <= 0;
		end
		else if (mem_req && !mem_ack && mem_is_rom) begin
			if (mem_write) begin
				mem_ack_r <= 1;            // djMEMC discards ROM writes
			end
			else begin
				ddram_addr     <= DDR_ROM_BASE | {12'd0, mem_addr[19:4], 1'b0};
				ddram_burstcnt <= 8'd2;
				ddram_rd       <= 1;
				ddr_rd_word    <= mem_addr[3:2];
				ddr_rd_beat1   <= 0;
				rom_line_valid <= 0;
				rom_line_tag   <= mem_addr[19:4];
				ddr_wait_data  <= 1;
			end
		end
		// The Ethernet mailbox comes last: single 64-bit beats, a few hundred a
		// second when the link is idle.  A ROM beat that arrives behind one waits
		// for it, which is one DDR3 round trip.  !eth_mem_accept: the requester
		// needs a clock to drop the request this block has just taken.
		else if ((eth_mem_rd || eth_mem_we) && !eth_mem_accept) begin
			ddram_addr     <= DDR_ETH_BASE | {17'd0, eth_mem_addr};
			ddram_din      <= eth_mem_wdata;
			ddram_be       <= 8'hFF;
			ddram_burstcnt <= 8'd1;
			ddram_we       <= eth_mem_we;
			ddram_rd       <= !eth_mem_we;
			ddr_wait_eth   <= !eth_mem_we;
			eth_mem_accept <= 1;
		end
		// RAM beats are sdram_beat32's; nothing here gates them, so a RAM
		// access never waits on the DDR3 side of this block.
	end

	if (ioctl_download && rom_index) rom_line_valid <= 0;
	if (reset && !ioctl_download) begin
		vram_ph <= 0;
		ddr_wait_data <= 0;
		// ddr_wait_eth is NOT cleared: the bridge will still answer that read, and the
		// answer must not be taken for the ROM's.
	end
	if (RESET) begin
		ioctl_pend <= 0;
		ioctl_wait <= 0;
	end
end

endmodule
