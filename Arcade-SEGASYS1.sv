//=========================================================
//  Arcade: SEGA SYSTEM 1  for MiSTer
//
//                          Copyright (c) 2019 MiSTer-X
//=========================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output	      VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

        // I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,
	
	input         OSD_STATUS
);

assign VGA_F1	 = 0;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS = llapi_osd;

assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;

`include "build_id.v" 

localparam CONF_STR = {
	"A.SEGASYS1;;",
	"-;",
        "F0,rom;", // allow loading of alternate ROMs
	"-;",
	"O1,Aspect Ratio,Original,Wide;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"OM,Serial Mode,Off,LLAPI;",
	"-;",
	"R0,Reset;",
	"J1,Trig1,Trig2,Start 1P,Start 2P,Coin;",
	"V,v",`BUILD_DATE
};

wire bCabinet = 1'b0;

wire [7:0] DSW0 = 8'hFF;
wire [7:0] DSW1 = 8'hFE;

////////////////////   CLOCKS   ///////////////////

wire clk_hdmi;
wire clk_48M;
wire clk_sys = clk_hdmi;

pll pll
(
	.rst(0),
	.refclk(CLK_50M),
	.outclk_0(clk_48M),
	.outclk_1(clk_hdmi)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire	    direct_video;


wire        ioctl_download;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;
wire [15:0] joystk1, joystk2;
wire [15:0] joystick_analog_0;
wire [15:0] joystick_analog_1;
wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	
	.status(status),
	.status_menumask({direct_video,menumask}),
	
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystk1),
	.joystick_1(joystk2),
	.joystick_analog_0(joystick_analog_0),
	.joystick_analog_1(joystick_analog_1),	

	.ps2_key(ps2_key)
);

////////////////////////////  LLAPI  ///////////////////////////////////

wire [31:0] llapi_buttons, llapi_buttons2;
wire [71:0] llapi_analog, llapi_analog2;
wire [7:0]  llapi_type, llapi_type2;
wire llapi_en, llapi_en2;

wire llapi_select = status[22];

wire llapi_latch_o, llapi_latch_o2, llapi_data_o, llapi_data_o2;

// Indexes:
// 0 = D+    = P1 Latch
// 1 = D-    = P1 Data
// 2 = TX-   = LLAPI Enable
// 3 = GND_d = N/C
// 4 = RX+   = P2 Latch
// 5 = RX-   = P2 Data

always_comb begin
	USER_OUT = 6'b111111;
	if (llapi_select) begin
		USER_OUT[0] = llapi_latch_o;
		USER_OUT[1] = llapi_data_o;
		USER_OUT[2] = ~(llapi_select & ~OSD_STATUS);
		USER_OUT[4] = llapi_latch_o2;
		USER_OUT[5] = llapi_data_o2;
	end
end

LLAPI llapi
(
	.CLK_50M(CLK_50M),
	.LLAPI_SYNC(vblank),
	.IO_LATCH_IN(USER_IN[0]),
	.IO_LATCH_OUT(llapi_latch_o),
	.IO_DATA_IN(USER_IN[1]),
	.IO_DATA_OUT(llapi_data_o),
	.ENABLE(llapi_select & ~OSD_STATUS),
	.LLAPI_BUTTONS(llapi_buttons),
	.LLAPI_ANALOG(llapi_analog),
	.LLAPI_TYPE(llapi_type),
	.LLAPI_EN(llapi_en)
);

LLAPI llapi2
(
	.CLK_50M(CLK_50M),
	.LLAPI_SYNC(vblank),
	.IO_LATCH_IN(USER_IN[4]),
	.IO_LATCH_OUT(llapi_latch_o2),
	.IO_DATA_IN(USER_IN[5]),
	.IO_DATA_OUT(llapi_data_o2),
	.ENABLE(llapi_select & ~OSD_STATUS),
	.LLAPI_BUTTONS(llapi_buttons2),
	.LLAPI_ANALOG(llapi_analog2),
	.LLAPI_TYPE(llapi_type2),
	.LLAPI_EN(llapi_en2)
);

// "J1,Skip,Start 1P,Start 2P,Coin;",

wire [15:0] joy_ll_a = { 8'd0,
	llapi_buttons[4],  llapi_buttons[22], llapi_buttons[5],  llapi_buttons[0], llapi_buttons[2],       // Coin Start-2P Start-1P trig1 trig2
	llapi_buttons[27], llapi_buttons[26], llapi_buttons[25], llapi_buttons[24]                         // d-pad
};

wire [15:0] joy_ll_b = { 8'd0,
	llapi_buttons2[22], llapi_buttons2[4],  llapi_buttons2[5],  llapi_buttons2[0], llapi_buttons2[2],  // Coin Start-2P Start-1P trig1 trig2
	llapi_buttons2[27], llapi_buttons2[26], llapi_buttons2[25], llapi_buttons2[24]                     // d-pad
};

wire llapi_osd = (llapi_buttons[26] && llapi_buttons[5] && llapi_buttons[0]) || (llapi_buttons2[26] && llapi_buttons2[5] && llapi_buttons2[0]);

wire [15:0] joy1 = joystk1 | joy_ll_a;
wire [15:0] joy2 = joystk2 | joy_ll_b;

reg [7:0] tno;
always @(posedge clk_sys) begin
	if (ioctl_index==0) tno <= 0;
	else if (ioctl_index==1) tno <= ioctl_dout;
end

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_trig1       <= pressed; // space
			'h014: btn_trig2       <= pressed; // ctrl
			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2

			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_trig1_2     <= pressed; // A
			'h01B: btn_trig2_2     <= pressed; // S
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_trig1 = 0;
reg btn_trig2 = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;

reg btn_start_1 = 0;
reg btn_start_2 = 0;
reg btn_coin_1  = 0;
reg btn_coin_2  = 0;
reg btn_up_2    = 0;
reg btn_down_2  = 0;
reg btn_left_2  = 0;
reg btn_right_2 = 0;
reg btn_trig1_2 = 0;
reg btn_trig2_2 = 0;


wire m_up2     = btn_up_2    | joy2[3];
wire m_down2   = btn_down_2  | joy2[2];
wire m_left2   = btn_left_2  | joy2[1];
wire m_right2  = btn_right_2 | joy2[0];
wire m_trig21  = btn_trig1_2 | joy2[4];
wire m_trig22  = btn_trig2_2 | joy2[5];

wire m_start1  = btn_one_player  | joy1[6] | joy2[6] | btn_start_1;
wire m_start2  = btn_two_players | joy1[7] | joy2[7] | btn_start_2;

wire m_up1     = btn_up      | joy1[3] | (bCabinet ? 1'b0 : m_up2);
wire m_down1   = btn_down    | joy1[2] | (bCabinet ? 1'b0 : m_down2);
wire m_left1   = btn_left    | joy1[1] | (bCabinet ? 1'b0 : m_left2);
wire m_right1  = btn_right   | joy1[0] | (bCabinet ? 1'b0 : m_right2);
wire m_trig11  = btn_trig1   | joy1[4] | (bCabinet ? 1'b0 : m_trig21);
wire m_trig12  = btn_trig2   | joy1[5] | (bCabinet ? 1'b0 : m_trig22);

wire m_coin1   = btn_one_player | btn_coin_1 | joy1[8];
wire m_coin2   = btn_two_players| btn_coin_2 | joy2[8];
wire m_coin    = (m_coin1|m_coin2);


///////////////////////////////////////////////////

wire hblank, vblank;
wire ce_vid;
wire hs, vs;
wire [2:0] r,g;
wire [1:0] b;

reg ce_pix;
always @(posedge clk_hdmi) begin
	reg old_clk;
	old_clk <= ce_vid;
	ce_pix  <= old_clk & ~ce_vid;
end

arcade_fx #(256,8) arcade_video
(
	.*,

	.clk_video(clk_hdmi),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.fx(status[5:3])
);

wire	      PCLK;
wire  [8:0] HPOS,VPOS;
wire  [7:0] POUT;
HVGEN hvgen
(
	.HPOS(HPOS),.VPOS(VPOS),.PCLK(PCLK),.iRGB(POUT),
	.oRGB({b,g,r}),.HBLK(hblank),.VBLK(vblank),.HSYN(hs),.VSYN(vs)
);
assign ce_vid = PCLK;


wire [15:0] AOUT;
assign AUDIO_L = AOUT;
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0; // unsigned PCM


///////////////////////////////////////////////////

wire iRST = RESET | status[0] | buttons[1] | ioctl_download;

wire [7:0] INP0 = ~{m_left1,m_right1,m_up1,m_down1,1'd0,m_trig12,m_trig11,1'd0}; 
wire [7:0] INP1 = ~{m_left2,m_right2,m_up2,m_down2,1'd0,m_trig22,m_trig21,1'd0}; 
wire [7:0] INP2 = ~{2'd0,m_start2,m_start1,3'd0, m_coin}; 


SEGASYSTEM1 GameCore ( 
	.clk48M(clk_48M),.reset(iRST),

	.INP0(INP0),.INP1(INP1),.INP2(INP2),
	.DSW0(DSW0),.DSW1(DSW1),

	.PH(HPOS),.PV(VPOS),.PCLK(PCLK),.POUT(POUT),
	.SOUT(AOUT),

	.ROMCL(clk_sys),.ROMAD(ioctl_addr),.ROMDT(ioctl_dout),.ROMEN(ioctl_wr & (ioctl_index==0))
);

endmodule

