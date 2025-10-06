`timescale 1ns / 1ps
module recv_mii #(
	parameter	MII_TYPE	=	"GMII",
	parameter	JUMBO		=	1,

	parameter	NMATCH_DENY	=	0,

	parameter	MII_WIDTH	=	(MII_TYPE =="25GMII") ? 64
							:	(MII_TYPE == "XGMII") ? 64
							:	(MII_TYPE ==  "GMII") ? 8 
							:	(MII_TYPE == "RGMII") ? 4 
							:	(MII_TYPE ==   "MII") ? 4
							:	0,
	parameter	MII_CTLW	=	(MII_TYPE =="25GMII") ? 8
							:	(MII_TYPE == "XGMII") ? 8
							:	(MII_TYPE ==  "GMII") ? 1 
							:	(MII_TYPE == "RGMII") ? 1 
							:	(MII_TYPE ==   "MII") ? 1
							:	0,
	parameter	DATA_WIDTH	=	(MII_TYPE =="25GMII") ? MII_WIDTH
							:	(MII_TYPE == "XGMII") ? MII_WIDTH
							:	8
)(
	input					clk,
	input					rst,

	(* mark_debug = "true" *)input	[MII_WIDTH-1:0]		mii_rx_d,
	(* mark_debug = "true" *)input	[MII_CTLW-1:0]		mii_rx_c,

	// PAUSE Frame send(1:on, 0:off)
	output						hw_wait,

	// Data IF(FIFO)
	(* mark_debug = "true" *)output						buf_wen,
	(* mark_debug = "true" *)output	[DATA_WIDTH-1:0]	buf_d,

	// Frame SRC/DST
	output	[47:0]				src_mac,
	output	[47:0]				dst_mac,
	input	[47:0]				own_mac,
	output	[15:0]				ptype,

	// SPIN Frame Header
	output						head_end,
	
	output	[7:0]				fport,
	output	[7:0]				dsize,
	output	[31:0]				daddr
);

	// Baseline state
	localparam	WAIT		= 0,
				PREAMBLE	= 1,
				DST			= 2,
				SRC			= 3,
				TYPE		= 4,
				FPORT		= 5,
				DSIZE		= 6,
				DADDR		= 7,
				FDATA		= 8,
				WGAP		= 9,
				FLOW_RECV	= 10;

	(* mark_debug = "true" *)reg		[3:0]		r_rx_state;

	(* mark_debug = "true" *)reg		[47:0]		r_rd_src_mac, r_rd_dst_mac;
	(* mark_debug = "true" *)reg		[15:0]		r_ptype;

	(* mark_debug = "true" *)reg		[7:0]		r_fport;
	(* mark_debug = "true" *)reg		[7:0]		r_dsize;
	(* mark_debug = "true" *)reg		[31:0]		r_daddr;

	(* mark_debug = "true" *)reg		[13:0]		r_rx_counter;

	(* mark_debug = "true" *)reg					receiving;

	(* mark_debug = "true" *)reg		[15:0]		r_flowtime, r_flowtime_buf;

	assign	src_mac	=	r_rd_src_mac;
	assign	dst_mac	=	r_rd_dst_mac;
	assign	ptype	=	r_ptype;

	assign	fport	=	r_fport;
	assign	dsize	=	r_dsize;
	assign	daddr	=	r_daddr;

	generate
		if (MII_TYPE == "MII") begin : MII_CORE
			reg				toggle;
			(* mark_debug = "true" *)reg				rx_valid;
			(* mark_debug = "true" *)reg	[7:0]		r_rxd;

			assign	buf_wen	=	rx_valid;
			assign	buf_d	=	r_rxd;

			always @(posedge clk) begin
				if (rst) begin
					toggle			<=	0;
					r_rx_counter	<=	0;
					r_rx_state		<=	WAIT;
					
					r_rd_src_mac	<=	0; 
					r_rd_dst_mac	<=	0;
					r_ptype			<=	0;

					r_fport			<=	0;
					r_dsize			<=	0;
					r_daddr			<=	0;

					r_rxd			<=	0;

					rx_valid		<=	1'b0;

					receiving		<=	0;
				end else begin
					toggle			<=	~toggle;
					case (r_rx_state)
						WAIT: begin
							if (mii_rx_c) begin
								toggle			<=	0;
								receiving		<=	1;
								r_rx_state		<=	PREAMBLE;

								r_rd_src_mac	<=	0; 
								r_rd_dst_mac	<=	0;
								r_ptype			<=	0;

								r_fport			<=	0;
								r_dsize			<=	0;
								r_daddr			<=	0;

								rx_valid		<=	1'b0;

								r_rxd			<=	0;
							end
						end
						PREAMBLE: begin
							if (mii_rx_d == 4'hD) begin
								toggle			<=	0;
								r_rx_counter	<=	0;
								r_rx_state		<=	DST;
							end else if (mii_rx_d == 4'h5) begin
								r_rx_state		<=	PREAMBLE;
							end else begin
								r_rx_state		<=	WGAP;
							end
						end
						DST: begin
							r_rd_dst_mac[(8*(5-r_rx_counter[3:1])+4*toggle)+:4]	<=	mii_rx_d;
							if(r_rx_counter >= 12-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	SRC;
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						SRC: begin
							r_rd_src_mac[(8*(5-r_rx_counter[3:1])+4*toggle)+:4]	<=	mii_rx_d;
							if(r_rx_counter >= 12-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	TYPE;
							end else begin
								if (NMATCH_DENY) begin
									if (!(r_rd_dst_mac == own_mac ||
										  r_rd_dst_mac == 48'hFFFFFF_FFFFFF ||			// Broadcast
										  r_rd_dst_mac == 48'h0180C2_000001 )) begin	// Multicast
										r_rx_state		<=	WGAP;	
									end
									r_rx_counter	<=	r_rx_counter + 1;
								end else begin
									r_rx_counter	<=	r_rx_counter + 1;
								end
							end
						end
						TYPE: begin
							r_ptype[(8*(1-r_rx_counter[1])+4*toggle)+:4]		<=	mii_rx_d;
							if(r_rx_counter >= 4-1) begin
								r_rx_counter	<=	0;
								if ({r_ptype[15:8], mii_rx_d, r_ptype[3:0]} == 16'h88_08) begin
									r_rx_state		<=	FLOW_RECV;
								end else begin
									r_rx_state		<=	FPORT;
								end
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						FPORT: begin
							r_fport[(4*toggle)+:4]		<=	mii_rx_d;
							if (toggle) begin
								r_rx_state		<=	DSIZE;
							end
						end
						DSIZE: begin
							r_dsize[(4*toggle)+:4]		<=	mii_rx_d;
							if (toggle) begin
								r_rx_state		<=	DADDR;
							end
						end
						DADDR: begin
							if (r_rx_counter <= 8) begin
								r_daddr[(8*(3-r_rx_counter[3:1])+4*toggle)+:4]	<=	mii_rx_d;
							end
							if(r_rx_counter >= 16-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	FDATA;
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						FDATA: begin
							if (!toggle && mii_rx_c) begin
								rx_valid	<=	1'b1;
							end else begin
								rx_valid	<=	1'b0;
							end
							
							r_rx_counter	<=	r_rx_counter + 1;

							if (toggle) begin
								r_rxd[7:4]		<=	mii_rx_d;
							end else begin
								r_rxd[3:0]		<=	mii_rx_d;
							end

							if (!mii_rx_c || (r_rx_counter >= (r_dsize << 5)*2)) begin
								r_rx_state		<=	WGAP;
								rx_valid		<=	1'b0;
							end
						end
						FLOW_RECV: begin
							r_rx_counter	<=	r_rx_counter + 1;
							if (!mii_rx_c) begin
								r_rx_state				<=	WGAP;
							end

							case (r_rx_counter) // PFC Pause frameもとりあえず対応
								1: begin
									if (mii_rx_d != 4'h0) begin
										r_rx_state				<=	WGAP;
									end
								end
								2: begin
									if (mii_rx_d != 4'h1) begin
										r_rx_state				<=	WGAP;
									end
								end
								3: begin
									if (mii_rx_d != 4'h0) begin
										r_rx_state				<=	WGAP;
									end
								end
								4: begin
									r_flowtime_buf[11:8]	<=	mii_rx_d;
								end
								5: begin
									r_flowtime_buf[15:12]	<=	mii_rx_d;
								end
								6: begin
									r_flowtime_buf[3:0]		<=	mii_rx_d;
								end
								7: begin
									r_flowtime_buf[7:4]		<=	mii_rx_d;
								end
								8: begin
									r_rx_state				<=	WGAP;
								end
								default: r_rx_state		<=	FLOW_RECV;
							endcase
						end
						WGAP: begin
							rx_valid		<=	1'b0;
							if (receiving) begin
								if (!mii_rx_c) begin
									receiving		<=	0;
									r_rx_counter	<=	0;
								end
							end else begin
								r_rx_state		<=	WAIT;
							end
						end
						default: begin
							receiving		<=	0;
							r_rx_counter	<=	0;
							r_rx_state		<=	WAIT;
						end
					endcase
				end
			end

			always @(posedge clk) begin
				if (rst) begin
					r_flowtime	<=	0;
				end else begin
					if (r_rx_state == FLOW_RECV && r_rx_counter == 8) begin
						r_flowtime	<=	r_flowtime_buf;
					end else begin
						if (r_flowtime != 0) begin
							r_flowtime	<=	r_flowtime - 1;
						end
					end
				end
			end

			assign	hw_wait	= (r_flowtime != 0);
		end else if (MII_TYPE == "RGMII") begin : MII_CORE
			reg				toggle;
			(* mark_debug = "true" *)reg				rx_valid;
			(* mark_debug = "true" *)reg	[7:0]		r_rxd;

			assign	buf_wen	=	rx_valid;
			assign	buf_d	=	r_rxd;

			always @(posedge clk or negedge clk) begin
				if (rst) begin
					toggle			<=	0;
					r_rx_counter	<=	0;
					r_rx_state		<=	WAIT;
					
					r_rd_src_mac	<=	0; 
					r_rd_dst_mac	<=	0;
					r_ptype			<=	0;

					r_fport			<=	0;
					r_dsize			<=	0;
					r_daddr			<=	0;

					r_rxd			<=	0;

					rx_valid		<=	1'b0;

					receiving		<=	0;
				end else begin
					toggle			<=	~toggle;
					case (r_rx_state)
						WAIT: begin
							if (mii_rx_c) begin
								toggle			<=	0;
								receiving		<=	1;
								r_rx_state		<=	PREAMBLE;

								r_rd_src_mac	<=	0; 
								r_rd_dst_mac	<=	0;
								r_ptype			<=	0;

								r_fport			<=	0;
								r_dsize			<=	0;
								r_daddr			<=	0;

								rx_valid		<=	1'b0;

								r_rxd			<=	0;
							end
						end
						PREAMBLE: begin
							if (mii_rx_d == 4'hD) begin
								toggle			<=	0;
								r_rx_counter	<=	0;
								r_rx_state		<=	DST;
							end else if (mii_rx_d == 4'h5) begin
								r_rx_state		<=	PREAMBLE;
							end else begin
								r_rx_state		<=	WGAP;
							end
						end
						DST: begin
							r_rd_dst_mac[(8*(5-r_rx_counter[3:1])+4*toggle)+:4]	<=	mii_rx_d;
							if(r_rx_counter >= 12-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	SRC;
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						SRC: begin
							r_rd_src_mac[(8*(5-r_rx_counter[3:1])+4*toggle)+:4]	<=	mii_rx_d;
							if(r_rx_counter >= 12-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	TYPE;
							end else begin
								if (NMATCH_DENY) begin
									if (!(r_rd_dst_mac == own_mac ||
										  r_rd_dst_mac == 48'hFFFFFF_FFFFFF ||			// Broadcast
										  r_rd_dst_mac == 48'h0180C2_000001 )) begin	// Multicast
										r_rx_state		<=	WGAP;	
									end
									r_rx_counter	<=	r_rx_counter + 1;
								end else begin
									r_rx_counter	<=	r_rx_counter + 1;
								end
							end
						end
						TYPE: begin
							r_ptype[(8*(1-r_rx_counter[1])+4*toggle)+:4]		<=	mii_rx_d;
							if(r_rx_counter >= 4-1) begin
								r_rx_counter	<=	0;
								if ({r_ptype[15:8], mii_rx_d, r_ptype[3:0]} == 16'h88_08) begin
									r_rx_state		<=	FLOW_RECV;
								end else begin
									r_rx_state		<=	FPORT;
								end
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						FPORT: begin
							r_fport[(4*toggle)+:4]		<=	mii_rx_d;
							if (toggle) begin
								r_rx_state		<=	DSIZE;
							end
						end
						DSIZE: begin
							r_dsize[(4*toggle)+:4]		<=	mii_rx_d;
							if (toggle) begin
								r_rx_state		<=	DADDR;
							end
						end
						DADDR: begin
							if (r_rx_counter <= 8) begin
								r_daddr[(8*(3-r_rx_counter[3:1])+4*toggle)+:4]	<=	mii_rx_d;
							end
							if(r_rx_counter >= 16-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	FDATA;
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						FDATA: begin
							if (!toggle && mii_rx_c) begin
								rx_valid	<=	1'b1;
							end else begin
								rx_valid	<=	1'b0;
							end
							
							r_rx_counter	<=	r_rx_counter + 1;

							if (toggle) begin
								r_rxd[7:4]		<=	mii_rx_d;
							end else begin
								r_rxd[3:0]		<=	mii_rx_d;
							end

							if (!mii_rx_c || (r_rx_counter >= (r_dsize << 5)*2)) begin
								r_rx_state		<=	WGAP;
								rx_valid		<=	1'b0;
							end
						end
						FLOW_RECV: begin
							r_rx_counter	<=	r_rx_counter + 1;
							if (!mii_rx_c) begin
								r_rx_state				<=	WGAP;
							end

							case (r_rx_counter) // PFC Pause frameもとりあえず対応
								1: begin
									if (mii_rx_d != 4'h0) begin
										r_rx_state				<=	WGAP;
									end
								end
								2: begin
									if (mii_rx_d != 4'h1) begin
										r_rx_state				<=	WGAP;
									end
								end
								3: begin
									if (mii_rx_d != 4'h0) begin
										r_rx_state				<=	WGAP;
									end
								end
								4: begin
									r_flowtime_buf[11:8]	<=	mii_rx_d;
								end
								5: begin
									r_flowtime_buf[15:12]	<=	mii_rx_d;
								end
								6: begin
									r_flowtime_buf[3:0]		<=	mii_rx_d;
								end
								7: begin
									r_flowtime_buf[7:4]		<=	mii_rx_d;
								end
								8: begin
									r_rx_state				<=	WGAP;
								end
								default: r_rx_state		<=	FLOW_RECV;
							endcase
						end
						WGAP: begin
							rx_valid		<=	1'b0;
							if (receiving) begin
								if (!mii_rx_c) begin
									receiving		<=	0;
									r_rx_counter	<=	0;
								end
							end else begin
								r_rx_state		<=	WAIT;
							end
						end
						default: begin
							receiving		<=	0;
							r_rx_counter	<=	0;
							r_rx_state		<=	WAIT;
						end
					endcase
				end
			end

			always @(posedge clk or negedge clk) begin
				if (rst) begin
					r_flowtime	<=	0;
				end else begin
					if (r_rx_state == FLOW_RECV && r_rx_counter == 8) begin
						r_flowtime	<=	r_flowtime_buf;
					end else begin
						if (r_flowtime != 0) begin
							r_flowtime	<=	r_flowtime - 1;
						end
					end
				end
			end

			assign	hw_wait	= (r_flowtime != 0);
		end else if (MII_TYPE == "GMII") begin : GMII_CORE
			(* mark_debug = "true" *)reg				rx_valid;
			(* mark_debug = "true" *)reg	[7:0]		r_rxd;	

			assign	buf_wen	=	rx_valid;
			assign	buf_d	=	r_rxd;

			always @(posedge clk) begin
				if (rst) begin
					r_rx_counter	<=	0;
					r_rx_state		<=	WAIT;
					
					r_rd_src_mac	<=	0; 
					r_rd_dst_mac	<=	0;
					r_ptype			<=	0;

					r_fport			<=	0;
					r_dsize			<=	0;
					r_daddr			<=	0;

					r_rxd			<=	0;

					rx_valid		<=	1'b0;
					receiving		<=	0;
				end else begin
					case (r_rx_state)
						WAIT: begin
							if (mii_rx_c) begin
								receiving		<=	1;
								r_rx_counter	<=	0;
								r_rx_state		<=	PREAMBLE;

								r_rd_src_mac	<=	0; 
								r_rd_dst_mac	<=	0;
								r_ptype			<=	0;

								r_fport			<=	0;
								r_dsize			<=	0;
								r_daddr			<=	0;

								rx_valid		<=	1'b0;

								r_rxd			<=	0;
							end
						end
						PREAMBLE: begin
							if (mii_rx_d == 8'hD5) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	DST;
							end else if (mii_rx_d == 8'h55) begin
								r_rx_state		<=	PREAMBLE;
							end else begin
								r_rx_state		<=	WGAP;
							end
						end
						DST: begin
							r_rd_dst_mac[(8*(5-r_rx_counter))+:8]	<=	mii_rx_d;
							if(r_rx_counter >= 6-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	SRC;
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						SRC: begin
							r_rd_src_mac[(8*(5-r_rx_counter))+:8]	<=	mii_rx_d;
							if(r_rx_counter >= 6-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	TYPE;
							end else begin
								if (NMATCH_DENY) begin
									if (!(r_rd_dst_mac == own_mac ||
										  r_rd_dst_mac == 48'hFFFFFF_FFFFFF ||
										  r_rd_dst_mac == 48'h0180C2_000001 )) begin
										r_rx_state		<=	WGAP;	
									end
									r_rx_counter	<=	r_rx_counter + 1;
								end else begin
									r_rx_counter	<=	r_rx_counter + 1;
								end
							end
						end
						TYPE: begin
							r_ptype[(8*(1-r_rx_counter))+:8]		<=	mii_rx_d;
							if(r_rx_counter >= 2-1) begin
								r_rx_counter	<=	0;
								if ({r_ptype[15:8], mii_rx_d} == 16'h88_08) begin
									r_rx_state		<=	FLOW_RECV;
								end else begin
									r_rx_state		<=	FPORT;
								end
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						FPORT: begin
							r_fport			<=	mii_rx_d;
							r_rx_state		<=	DSIZE;
						end
						DSIZE: begin
							r_dsize			<=	mii_rx_d;
							r_rx_state		<=	DADDR;
						end
						DADDR: begin
							if (r_rx_counter <= 4) begin
								r_daddr[(8*(3-r_rx_counter))+:8]		<=	mii_rx_d;
							end
							if(r_rx_counter >= 8-1) begin
								r_rx_counter	<=	0;
								r_rx_state		<=	FDATA;
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
							end
						end
						FDATA: begin
							r_rx_counter	<=	r_rx_counter + 1;
							rx_valid		<=	1'b1;
							r_rxd			<=	mii_rx_d;
							if (mii_rx_d == 0 && mii_rx_c == 0 ||
								r_rx_counter >= (r_dsize << 5)) begin
								r_rx_state		<=	WGAP;
								rx_valid		<=	1'b0;
							end
						end
						FLOW_RECV: begin
							r_rx_counter	<=	r_rx_counter + 1;
							if (mii_rx_d == 0 && mii_rx_c == 0) begin
								r_rx_state		<=	WGAP;
							end

							case (r_rx_counter) // PFC Pause frameもとりあえず対応
								0: begin
									if (mii_rx_d != 8'h00 || mii_rx_d != 8'h01) begin
										r_rx_state				<=	WGAP;
									end
								end 
								1: begin
									if (mii_rx_d != 8'h01) begin
										r_rx_state				<=	WGAP;
									end
								end
								2: begin
									r_flowtime_buf[15:8]	<=	mii_rx_d;
								end
								3: begin
									r_flowtime_buf[7:0]		<=	mii_rx_d;
								end
								4: begin
									r_rx_state				<=	WGAP;
								end
								default: r_rx_state		<=	FLOW_RECV;
							endcase
						end
						WGAP: begin
							rx_valid		<=	1'b0;
							if (receiving) begin
								if (!mii_rx_c) begin
									receiving		<=	0;
									r_rx_counter	<=	0;
								end
							end else begin
								r_rx_state		<=	WAIT;
							end
						end
						default: begin
							receiving		<=	0;
							r_rx_counter	<=	0;
							r_rx_state		<=	WAIT;
						end
					endcase
				end
			end

			always @(posedge clk) begin
				if (rst) begin
					r_flowtime	<=	0;
				end else begin
					if (r_rx_state == FLOW_RECV && r_rx_counter == 4) begin
						r_flowtime	<=	r_flowtime_buf;
					end else begin
						if (r_flowtime != 0) begin
							r_flowtime	<=	r_flowtime - 1;
						end
					end
				end
			end

			assign	hw_wait	= (r_flowtime != 0);
		end else if (MII_TYPE == "XGMII" || MII_TYPE == "25GMII") begin : XGMII_CORE
			wire	[63:0]	xgmii_rxd;
			wire	[7:0]	xgmii_rxc;

			(* mark_debug = "true" *)reg				rx_valid;
			(* mark_debug = "true" *)reg	[63:0]		rx_data;	

			assign	buf_wen	=	rx_valid;
			assign	buf_d	=	rx_data;

			xgmiisync xgmiisync_0 (
				.sys_rst(rst),
				.xgmii_rx_clk(clk),
				.xgmii_rxd_i(mii_rx_d),
				.xgmii_rxc_i(mii_rx_c),
				.xgmii_rxd_o(xgmii_rxd),
				.xgmii_rxc_o(xgmii_rxc)
			);

			always @(posedge clk) begin
				if (rst) begin
					r_rx_counter	<=	0;
					r_rx_state		<=	WAIT;
					
					r_rd_src_mac	<=	0; 
					r_rd_dst_mac	<=	0;
					r_ptype			<=	0;

					r_fport			<=	0;
					r_dsize			<=	0;
					r_daddr			<=	0;

					rx_valid		<=	1'b0;
					receiving		<=	0;
				end else begin
					case (r_rx_state)
						WAIT: begin
							if (xgmii_rxc[0] && xgmii_rxd[7:0] == 8'hfb) begin
								receiving		<=	1;
								r_rx_counter	<=	0;
								r_rx_state		<=	DST;

								r_rd_src_mac	<=	0; 
								r_rd_dst_mac	<=	0;
								r_ptype			<=	0;

								r_fport			<=	0;
								r_dsize			<=	0;
								r_daddr			<=	0;

								rx_valid		<=	1'b0;
							end
						end
						DST: begin
							r_rd_dst_mac		<=	{xgmii_rxd[7:0],xgmii_rxd[15:8],xgmii_rxd[23:16],xgmii_rxd[31:24],xgmii_rxd[39:32],xgmii_rxd[47:40]};
							r_rd_src_mac[47:32]	<=	{xgmii_rxd[55:48], xgmii_rxd[63:56]};
							if (NMATCH_DENY) begin
								if (!({xgmii_rxd[7:0],xgmii_rxd[15:8],xgmii_rxd[23:16],xgmii_rxd[31:24],xgmii_rxd[39:32],xgmii_rxd[47:40]} == own_mac ||
									  {xgmii_rxd[7:0],xgmii_rxd[15:8],xgmii_rxd[23:16],xgmii_rxd[31:24],xgmii_rxd[39:32],xgmii_rxd[47:40]} == 48'hFFFFFF_FFFFFF ||
									  {xgmii_rxd[7:0],xgmii_rxd[15:8],xgmii_rxd[23:16],xgmii_rxd[31:24],xgmii_rxd[39:32],xgmii_rxd[47:40]} == 48'h0180C2_000001 )) begin
									r_rx_state		<=	WGAP;	
								end else begin
									r_rx_state		<=	SRC;
									r_rx_counter	<=	r_rx_counter + 1;
								end
							end else begin
								r_rx_counter	<=	r_rx_counter + 1;
								r_rx_state		<=	SRC;
							end
						end
						SRC: begin
							r_rd_src_mac[31:0]	<=	{xgmii_rxd[7:0],xgmii_rxd[15:8],xgmii_rxd[23:16],xgmii_rxd[31:24]};
							r_ptype				<=	{xgmii_rxd[39:32],xgmii_rxd[47:40]};
							r_fport				<=	xgmii_rxd[55:48];
							r_dsize				<=	xgmii_rxd[63:56];

							if ({xgmii_rxd[39:32],xgmii_rxd[47:40]} == 16'h88_08 && ({xgmii_rxd[55:48], xgmii_rxd[63:56]} == 16'h0001 || {xgmii_rxd[55:48], xgmii_rxd[63:56]} == 16'h0101)) begin
								r_rx_state		<=	FLOW_RECV;
								r_rx_counter	<=	0;
							end else begin
								r_rx_state		<=	DADDR;
							end
						end
						DADDR: begin
							r_daddr			<=	{xgmii_rxd[7:0],xgmii_rxd[15:8],xgmii_rxd[23:16],xgmii_rxd[31:24]};
							r_rx_state		<=	FDATA;
							r_rx_counter	<=	0;
						end
						FDATA: begin
							if (r_rx_counter <= 40) begin
								rx_data		<=	{xgmii_rxd[7:0], xgmii_rxd[15:8], xgmii_rxd[23:16], xgmii_rxd[31:24], xgmii_rxd[39:32], xgmii_rxd[47:40], xgmii_rxd[55:48], xgmii_rxd[63:56]};
								r_rx_counter	<=	r_rx_counter + 8;
								rx_valid	<=	1'b1;
							end else if (r_rx_counter >= (r_dsize << 5)) begin
								rx_valid		<=	1'b0;
								rx_data			<=	64'h0;
								r_rx_counter	<=	0;
								r_rx_state		<=	WGAP;
								receiving		<=	0;
							end else begin
								rx_data		<=	{xgmii_rxd[7:0], xgmii_rxd[15:8], xgmii_rxd[23:16], xgmii_rxd[31:24], xgmii_rxd[39:32], xgmii_rxd[47:40], xgmii_rxd[55:48], xgmii_rxd[63:56]};
								r_rx_counter	<=	r_rx_counter + 8;
								rx_valid	<=	1'b1;
							end
						end
						FLOW_RECV: begin
							if (r_rx_counter != 0) begin
								r_rx_state		<=	WGAP;
							end else begin
								r_flowtime_buf	<=	{xgmii_rxd[7:0],xgmii_rxd[15:8]};
							end
							r_rx_counter	<=	r_rx_counter + 1;
						end
						WGAP: begin
							rx_valid		<=	1'b0;
							rx_data			<=	64'h0;
							if (receiving) begin
								if (xgmii_rxc == 8'hFF) begin
									receiving		<=	0;
									r_rx_counter	<=	0;
								end
							end else begin
								r_rx_state		<=	WAIT;
							end
						end
						default: begin
							receiving		<=	0;
							r_rx_counter	<=	0;
							r_rx_state		<=	WAIT;
						end
					endcase
				end
			end

			always @(posedge clk) begin
				if (rst) begin
					r_flowtime	<=	0;
				end else begin
					if (r_rx_state == FLOW_RECV && r_rx_counter == 1) begin
						r_flowtime	<=	r_flowtime_buf;
					end else begin
						if (r_flowtime != 0) begin
							r_flowtime	<=	r_flowtime - 1;
						end
					end
				end
			end

			assign	hw_wait	= (r_flowtime != 0);
		end else begin
			unimplement unimplement(); end
	endgenerate
endmodule
