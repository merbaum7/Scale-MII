`timescale 1ns / 1ps
module send_mii #(
	parameter	MII_TYPE	=	"GMII",
	parameter	MII_BUFLEN	=	16,
	parameter	JUMBO		=	1,

	parameter	MII_WIDTH	=	(MII_TYPE =="25GMII") ? 64
							:	(MII_TYPE == "XGMII") ? 64
							:	(MII_TYPE ==  "GMII") ? 8 
							:	(MII_TYPE ==   "MII") ? 4
							:	0,
	parameter	MII_CTLW	=	(MII_TYPE =="25GMII") ? 8
							:	(MII_TYPE == "XGMII") ? 8
							:	(MII_TYPE ==  "GMII") ? 1
							:	(MII_TYPE ==   "MII") ? 1
							:	0,
	parameter	DATA_WIDTH	=	(MII_TYPE =="25GMII") ? MII_WIDTH
							:	(MII_TYPE == "XGMII") ? MII_WIDTH
							:	8,

	parameter	PARAM_REG	=	0
)(
	input						clk,
	input						rst,

	output	[MII_WIDTH-1:0]		mii_tx_d,
	output	[MII_CTLW-1:0]		mii_tx_c,

	// PAUSE Frame send(1:on, 0:off)
	input						hw_wait,

	// Force send
	input						force_send,

	// Data IF(FIFO)
	input						buf_clk,
	input						buf_wen,
	input	[DATA_WIDTH-1:0]	buf_d,
	output						buf_full,

	// Frame SRC/DST
	input	[47:0]				src_mac,
	input	[47:0]				dst_mac,
	input	[15:0]				ptype,

	// SPIN Frame Header
	output						head_end,

	input	[7:0]				fport,
	input	[7:0]				dsize,
	input	[31:0]				daddr,
	input	[31:0]				opts,

	output						send_done
);

	// Baseline state
	localparam	WAIT		= 0,
				PREAMBLE	= 1,
				FDATA		= 2,
				FCS			= 3,
				WGAP		= 4;

	localparam	MAX_SIZE	=	(JUMBO)	?	8192+16	:	1504+16;

	wire	[47:0]				inner_dst_mac;
	wire	[15:0]				inner_ptype;
	wire	[7:0]				inner_fport;
	wire	[7:0]				inner_dsize;
	wire	[31:0]				inner_daddr;
	wire	[31:0]				inner_option;

	// state register
	reg		[3:0]				r_tx_state;

	// control register
	reg							r_crc_init;
	wire						w_crc_en;
	wire	[31:0]				w_crc_data;
	
	// pause state [0: no_pause, 1: pause_start, 2: pause_end, 3: pause_continue]
	reg		[1:0]				r_flow;

	reg		[13:0]				r_tx_counter;

	// send data
	reg		[DATA_WIDTH-1:0]	r_txd;
	reg		[MII_CTLW-1:0]		r_txc;

	wire	[DATA_WIDTH-1:0]	w_dout;
	wire						w_dout_en;
	wire						w_aemp;
	wire						w_emp;

	wire	[DATA_WIDTH-1:0]	w_crc_in;

	// DST, PTYPE set register
	generate
		if (PARAM_REG == 1 || PARAM_REG == "TRUE" || PARAM_REG == "true") begin
			reg	[47:0]	r_dst_mac;
			reg	[15:0]	r_ptype;
			reg	[7:0]	r_fport;
			reg	[7:0]	r_dsize;
			reg	[31:0]	r_daddr;
			reg	[31:0]	r_opts;
			always @(posedge clk) begin
				if (r_tx_state == WAIT && !w_aemp) begin
					{r_dst_mac, r_ptype}	<=	{dst_mac, ptype};
					{r_fport, r_dsize}		<=	{fport, dsize};
					{r_daddr}				<=	{daddr};
					{r_opts}				<=	{opts};
				end
			end
			assign	inner_dst_mac	=	r_dst_mac;
			assign	inner_ptype		=	r_ptype;
			assign	inner_fport		=	r_fport;
			assign	inner_dsize		=	r_dsize;
			assign	inner_daddr		=	r_daddr;
			assign	inner_option	=	r_opts;
		end else if (PARAM_REG == 0 || PARAM_REG == "FALSE" || PARAM_REG == "false") begin
			assign	inner_dst_mac	=	dst_mac;
			assign	inner_ptype		=	ptype;
			assign	inner_fport		=	fport;
			assign	inner_dsize		=	dsize;
			assign	inner_daddr		=	daddr;
			assign	inner_option	=	opts;
		end
	endgenerate

	reg	[1:0]	send_done_reg;

	// Frame send done signal
	always @(posedge clk) begin
		if(rst) begin
			send_done_reg	<=	2'b0;
		end else begin
			send_done_reg	<=	{send_done_reg[0], (r_tx_state == WGAP)};
		end
	end
	assign	send_done	=	~send_done_reg[1] & send_done_reg[0];

	// MII Core
	generate
		if (MII_TYPE == "MII") begin : MII_CORE
			reg		r_crc_en;
			reg		r_toggle;

			reg		[3:0]	r_txd_mii;

			wire	w_stop_ren = (r_tx_counter == 14'h0) || (r_tx_counter >= (((inner_dsize+1) << 5)+32));
			
			assign	mii_tx_d	=	r_txd_mii;
			assign	mii_tx_c	=	r_txc;

			assign	w_dout_en	=	(r_tx_state == FDATA && r_tx_counter >= 14'h18 && !w_stop_ren) && !r_toggle;
			assign	w_crc_in	=	r_txd;
			assign	w_crc_en	=	r_crc_en;

			assign	head_end	=	(r_tx_state == FDATA) && (r_tx_counter == 14'h17) && !r_toggle;
			
			always @(posedge clk) begin
				if (rst) begin
					r_crc_init		<=	1;
					r_crc_en		<=	0;
					r_flow			<=	0;
					r_tx_state		<=	WAIT;
					r_tx_counter	<=	0;
					r_toggle		<=	0;
					{r_txc, r_txd}		<= {1'b0, 8'h00};
					r_txd_mii			<=	4'h0;
				end else begin
					case (r_tx_state)
					WAIT: begin
						{r_txc, r_txd}		<= {1'b0, 8'h00};
						r_txd_mii			<=	4'h0;

						// (recv flow control) or (flow state) or (exist send data)
						if ( hw_wait | r_flow != 0 | !w_aemp | force_send ) begin
							r_tx_state	<=	PREAMBLE;
						end
						r_flow			<=	{r_flow[0],(hw_wait)};
						r_crc_init		<=	1;
						r_tx_counter	<=	0;
						r_toggle		<=	0;
					end
					PREAMBLE: begin
						if (r_tx_counter == 15)begin
							{r_txc, r_txd_mii}	<=	{1'b1, 4'hD};
							r_crc_en			<=	0;
							r_tx_counter		<=	0;
							r_tx_state			<=	FDATA;
						end else begin
							{r_txc, r_txd_mii}	<=	{1'b1, 4'h5};
							r_tx_counter		<=	r_tx_counter + 1;
							r_crc_en			<=	0;
						end
						r_txd			<=	8'h0;
						r_crc_init		<=	0;						
					end
					FDATA: begin
						if (r_toggle == 0) begin
							if (r_tx_counter >= 14'd63 && (r_flow != 0 || w_aemp || r_tx_counter >= (MAX_SIZE-9) || r_tx_counter >= ((((inner_dsize+1) << 5)+32)))) begin
								r_tx_counter	<=	0;
								r_crc_en		<=	0;
							end else begin
								r_crc_en		<=	0;
							end
						end else begin
							r_crc_en		<=	1;
							r_tx_counter	<=	r_tx_counter + 1;
						end
						r_toggle	<=	~r_toggle;

						case (r_tx_counter)
							14'h00: begin // Write header (destination)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h01};
									if (r_toggle == 0) begin
										r_txd_mii	<=	4'h1;
									end else begin
										r_txd_mii	<=	4'h0;
									end
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[47:40]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dst_mac[43:40];
									end else begin
										r_txd_mii	<=	inner_dst_mac[47:44];
									end
								end
							end
							14'h01: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h80};
									if (r_toggle == 0) begin
										r_txd_mii	<=	4'h0;
									end else begin
										r_txd_mii	<=	4'h8;
									end
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[39:32]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dst_mac[35:32];
									end else begin
										r_txd_mii	<=	inner_dst_mac[39:36];
									end
								end
							end
							14'h02: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'hC2};
									if (r_toggle == 0) begin
										r_txd_mii	<=	4'h2;
									end else begin
										r_txd_mii	<=	4'hC;
									end
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[31:24]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dst_mac[27:24];
									end else begin
										r_txd_mii	<=	inner_dst_mac[31:28];
									end
								end
							end
							14'h03: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii	<=	4'h0;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[23:16]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dst_mac[19:16];
									end else begin
										r_txd_mii	<=	inner_dst_mac[23:20];
									end
								end
							end
							14'h04: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii	<=	4'h0;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[15:8]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dst_mac[11:8];
									end else begin
										r_txd_mii	<=	inner_dst_mac[15:12];
									end
								end
							end
							14'h05: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h01};
									if (r_toggle == 0) begin
										r_txd_mii	<=	4'h0;
									end else begin
										r_txd_mii	<=	4'h1;
									end
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[7:0]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dst_mac[3:0];
									end else begin
										r_txd_mii	<=	inner_dst_mac[7:4];
									end
								end
							end
							14'h06: begin // Write header (source)
								{r_txc, r_txd}	<=	{1'b1, src_mac[47:40]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	src_mac[43:40];
								end else begin
									r_txd_mii	<=	src_mac[47:44];
								end
							end
							14'h07: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[39:32]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	src_mac[35:32];
								end else begin
									r_txd_mii	<=	src_mac[39:36];
								end
							end
							14'h08: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[31:24]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	src_mac[27:24];
								end else begin
									r_txd_mii	<=	src_mac[31:28];
								end
							end
							14'h09: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[23:16]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	src_mac[19:16];
								end else begin
									r_txd_mii	<=	src_mac[23:20];
								end
							end
							14'h0A: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[15:8]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	src_mac[11:8];
								end else begin
									r_txd_mii	<=	src_mac[15:12];
								end
							end
							14'h0B: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[7:0]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	src_mac[3:0];
								end else begin
									r_txd_mii	<=	src_mac[7:4];
								end
							end
							14'h0C: begin // (type)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h88};
									r_txd_mii		<=	4'h8;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_ptype[15:8]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_ptype[11:8];
									end else begin
										r_txd_mii	<=	inner_ptype[15:12];
									end
								end
							end
							14'h0D: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h08};
									if (r_toggle == 0) begin
										r_txd_mii	<=	4'h8;
									end else begin
										r_txd_mii	<=	4'h0;
									end
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_ptype[7:0]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_ptype[3:0];
									end else begin
										r_txd_mii	<=	inner_ptype[7:4];
									end
								end
							end
							14'h0E: begin // (fpga port | flow: control code)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii	<=	4'h0;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_fport};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_fport[3:0];
									end else begin
										r_txd_mii	<=	inner_fport[7:4];
									end
								end
							end
							14'h0F: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h01};
									if (r_toggle == 0) begin
										r_txd_mii	<=	4'h1;
									end else begin
										r_txd_mii	<=	4'h0;
									end
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dsize[7:0]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_dsize[3:0];
									end else begin
										r_txd_mii	<=	inner_dsize[7:4];
									end
								end
							end
							14'h10: begin // (daddr | flow: wait time)
								if (r_flow == 2'b10) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii		<=	4'h0;
								end else if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'hff};
									r_txd_mii		<=	4'hf;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[31:24]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_daddr[27:24];
									end else begin
										r_txd_mii	<=	inner_daddr[31:28];
									end
								end
							end
							14'h11: begin 
								if (r_flow == 2'b10) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii		<=	4'h0;
								end else if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'hff};
									r_txd_mii		<=	4'hf;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[23:16]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_daddr[19:16];
									end else begin
										r_txd_mii	<=	inner_daddr[23:20];
									end
								end
							end
							14'h12: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii		<=	4'h0;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[15:8]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_daddr[11:8];
									end else begin
										r_txd_mii	<=	inner_daddr[15:12];
									end
								end
							end
							14'h13: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
									r_txd_mii		<=	4'h0;
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[7:0]};
									if (r_toggle == 0) begin
										r_txd_mii	<=	inner_daddr[3:0];
									end else begin
										r_txd_mii	<=	inner_daddr[7:4];
									end
								end
							end
							14'h14: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								//r_txd_mii		<=	4'h0;
								{r_txc, r_txd}	<=	{1'b1, inner_option[31:24]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	inner_option[27:24];
								end else begin
									r_txd_mii	<=	inner_option[31:28];
								end
							end
							14'h15: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								//r_txd_mii		<=	4'h0;
								{r_txc, r_txd}	<=	{1'b1, inner_option[23:16]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	inner_option[19:16];
								end else begin
									r_txd_mii	<=	inner_option[23:20];
								end
							end
							14'h16: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								//r_txd_mii		<=	4'h0;
								{r_txc, r_txd}	<=	{1'b1, inner_option[15:8]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	inner_option[11:8];
								end else begin
									r_txd_mii	<=	inner_option[15:12];
								end
							end
							14'h17: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								//r_txd_mii		<=	4'h0;
								{r_txc, r_txd}	<=	{1'b1, inner_option[7:0]};
								if (r_toggle == 0) begin
									r_txd_mii	<=	inner_option[3:0];
								end else begin
									r_txd_mii	<=	inner_option[7:4];
								end
							end
							default: begin
								if (r_toggle == 0) begin
									{r_txc, r_txd}	<= {1'b1, w_dout[7:0]};
									r_txd_mii	<=	r_txd[3:0];
								end else begin
									r_txd_mii	<=	r_txd[7:4];
								end
								if (r_tx_counter >= 14'd63 && r_toggle == 0) begin
									if (r_flow != 0 || w_aemp || r_tx_counter >= (MAX_SIZE-9) || r_tx_counter >= ((((inner_dsize+1) << 5)+32))) begin
										r_tx_state		<=	FCS;
									end
								end 
							end
						endcase
					end
					FCS: begin
						if (r_tx_counter == 8) begin
							r_tx_state		<=	WGAP;
							r_tx_counter	<=	0;
							r_crc_en		<=	0;
							{r_txc, r_txd}	<=	{1'b0, 8'h0};
							r_txd_mii		<=	4'h0;
						end else if (r_tx_counter <= 7) begin
							r_tx_counter	<=	r_tx_counter + 1;
							r_crc_en		<=	0;
							{r_txc, r_txd}	<=	{1'b1, 4'h0, w_crc_data[(4*r_tx_counter)+:4]};
							r_txd_mii		<=	w_crc_data[(4*r_tx_counter)+:4];
						end else begin
							r_tx_counter	<=	r_tx_counter + 1;
							r_crc_en		<=	0;
							{r_txc, r_txd}	<=	{1'b0, 8'h0};
							r_txd_mii		<=	4'h0;
						end
					end
					WGAP: begin
						{r_txc, r_txd}	<= {1'b0, 8'h0};
						r_txd_mii		<=	4'h0;
						if (r_tx_counter >= 24) begin
							r_tx_state		<=	WAIT;
							r_tx_counter	<=	0;
						end else begin
							r_tx_counter	<=	r_tx_counter + 1;
						end
					end
					default: r_tx_state	<=	WAIT;
					endcase
				end
			end
		end else if (MII_TYPE == "GMII") begin : GMII_CORE
			reg		r_crc_en;
			
			assign	mii_tx_d	=	r_txd;
			assign	mii_tx_c	=	r_txc;

			assign	w_dout_en	=	(r_tx_state == FDATA && r_tx_counter >= 14'h18);
			assign	w_crc_in	=	r_txd;
			assign	w_crc_en	=	r_crc_en;

			assign	head_end	=	(r_tx_state == FDATA) && (r_tx_counter == 14'h17);
			
			always @(posedge clk) begin
				if (rst) begin
					r_crc_init		<=	1;
					r_crc_en		<=	0;
					r_flow			<=	0;
					r_tx_state		<=	WAIT;
					r_tx_counter	<=	0;
					{r_txc, r_txd}		<= {1'b0, 8'h00};
				end else begin
					case (r_tx_state)
					WAIT: begin
						{r_txc, r_txd}		<= {1'b0, 8'h00};

						// (recv flow control) or (flow state) or (exist send data)
						if ( hw_wait | r_flow != 0 | !w_aemp | force_send ) begin
							r_tx_state	<=	PREAMBLE;
						end
						r_flow			<=	{r_flow[0],(hw_wait)};
						r_crc_init		<=	1;
						r_tx_counter	<=	0;
					end
					PREAMBLE: begin
						if (r_tx_counter == 7)begin
							{r_txc, r_txd}		<=	{1'b1, 8'hD5};
							r_crc_en			<=	0;
							r_tx_counter		<=	0;
							r_tx_state			<=	FDATA;
						end else begin
							{r_txc, r_txd}		<=	{1'b1, 8'h55};
							r_tx_counter		<=	r_tx_counter + 1;
							r_crc_en			<=	0;
						end
						r_crc_init		<=	0;						
					end
					FDATA: begin
						r_tx_counter	<=	r_tx_counter + 1;
						r_crc_en		<=	1;
						case (r_tx_counter)
							14'h00: begin // Write header (destination)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h01};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[47:40]};
								end
							end
							14'h01: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h80};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[39:32]};
								end
							end
							14'h02: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'hC2};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[31:24]};
								end
							end
							14'h03: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[23:16]};
								end
							end
							14'h04: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[15:8]};
								end
							end
							14'h05: begin
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h01};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dst_mac[7:0]};
								end
							end
							14'h06: begin // Write header (source)
								{r_txc, r_txd}	<=	{1'b1, src_mac[47:40]};
							end
							14'h07: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[39:32]};
							end
							14'h08: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[31:24]};
							end
							14'h09: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[23:16]};
							end
							14'h0A: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[15:8]};
							end
							14'h0B: begin
								{r_txc, r_txd}	<=	{1'b1, src_mac[7:0]};
							end
							14'h0C: begin // (type)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h88};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_ptype[15:8]};
								end
							end
							14'h0D: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h08};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_ptype[7:0]};
								end
							end
							14'h0E: begin // (fpga port | flow: control code)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_fport};
								end
							end
							14'h0F: begin // (Data size | flow: control code)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h01};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_dsize};
								end
							end
							14'h10: begin // (daddr | flow: wait time)
								if (r_flow == 2'b10) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'hff};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[31:24]};
								end
							end
							14'h11: begin 
								if (r_flow == 2'b10) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'hff};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[23:16]};
								end
							end
							14'h12: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[15:8]};
								end
							end
							14'h13: begin 
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{1'b1, 8'h00};
								end else begin
									{r_txc, r_txd}	<=	{1'b1, inner_daddr[7:0]};
								end
							end
							14'h14: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								{r_txc, r_txd}	<=	{1'b1, inner_option[31:24]};
							end
							14'h15: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								{r_txc, r_txd}	<=	{1'b1, inner_option[23:16]};
							end
							14'h16: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								{r_txc, r_txd}	<=	{1'b1, inner_option[15:8]};
							end
							14'h17: begin 
								//{r_txc, r_txd}	<=	{1'b1, 8'h00};
								{r_txc, r_txd}	<=	{1'b1, inner_option[7:0]};
							end
							default: begin
								{r_txc, r_txd}	<= {1'b1, w_dout[7:0]};
								if (r_tx_counter >= 14'd63) begin
									if (r_flow != 0 || w_aemp || r_tx_counter >= (MAX_SIZE-9)  || r_tx_counter >= ((((inner_dsize+1) << 5)+32)-1)) begin
										r_tx_state		<=	FCS;
										r_tx_counter	<=	0;
									end
								end 
							end
						endcase
					end
					FCS: begin
						if (r_tx_counter == 4) begin
							r_tx_state		<=	WGAP;
							r_tx_counter	<=	0;
							{r_txc, r_txd}		<= {1'b0, 8'h00};
						end else if (r_tx_counter <= 3) begin
							r_tx_counter	<=	r_tx_counter + 1;
							r_crc_en		<=	0;
							{r_txc, r_txd}		<= {1'b1, w_crc_data[(8*r_tx_counter)+:8]};
						end else begin
							r_tx_counter	<=	r_tx_counter + 1;
							r_crc_en		<=	0;
							{r_txc, r_txd}		<= {1'b0, 8'h00};
						end
					end
					WGAP: begin
						{r_txc, r_txd}		<= {1'b0, 8'h00};
						if (r_tx_counter >= 12) begin
							r_tx_state		<=	WAIT;
							r_tx_counter	<=	0;
						end else begin
							r_tx_counter	<=	r_tx_counter + 1;
						end
					end
					default: r_tx_state	<=	WAIT;
					endcase
				end
			end
		end else if (MII_TYPE == "XGMII" || MII_TYPE == "25GMII") begin : XGMII_CORE
			assign	w_crc_en	=	~r_crc_init;

			assign	mii_tx_d	=	r_txd;
			assign	mii_tx_c	=	r_txc;

			assign	w_dout_en	=	(r_tx_state == FDATA) && (r_tx_counter[13:3] >= 11'h3);
			assign	w_crc_in	=	r_txd;

			assign	head_end	=	(r_tx_state == FDATA) && (r_tx_counter[13:3] == 11'h3);

			always @(posedge clk) begin
				if (rst) begin
					r_crc_init		<=	1;
					r_flow			<=	0;
					r_tx_state		<=	WAIT;
					r_tx_counter	<=	0;
					{r_txc, r_txd}	<= {8'hff, 64'h07_07_07_07_07_07_07_07};
				end else begin
					case (r_tx_state)
					WAIT: begin
						{r_txc, r_txd}	<= {8'hff, 64'h07_07_07_07_07_07_07_07};

						// (recv flow control) or (flow state) or (exist send data)
						if ( hw_wait | r_flow != 0 | !w_aemp | force_send ) begin
							r_tx_state	<=	PREAMBLE;
						end
						r_flow			<=	{r_flow[0],(hw_wait)};
						r_crc_init		<=	1;
						r_tx_counter	<=	0;
					end
					PREAMBLE: begin
						{r_txc, r_txd}	<=	{8'h01, 64'hd5_55_55_55_55_55_55_fb};
						r_tx_state		<=	FDATA;
						r_crc_init		<=	1;
					end
					FDATA: begin
						r_crc_init		<=	0;
						r_tx_counter	<=	r_tx_counter + 8;
						case (r_tx_counter[13:3])
							11'h00: begin // Write header (destination and source)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{8'h00, src_mac[39:32], src_mac[47:40], 8'h01, 8'h00, 8'h00, 8'hC2, 8'h80, 8'h01};
								end else begin
									{r_txc, r_txd}	<=	{8'h00, src_mac[39:32], src_mac[47:40], inner_dst_mac[7:0], inner_dst_mac[15:8], inner_dst_mac[23:16], inner_dst_mac[31:24], inner_dst_mac[39:32], inner_dst_mac[47:40]};
								end
							end
							11'h01: begin // (source and type)
								if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{8'h00, 8'h01, 8'h00, 8'h08, 8'h88, src_mac[7:0], src_mac[15:8], src_mac[23:16], src_mac[31:24]};
								end else begin
									{r_txc, r_txd}	<=	{8'h00, inner_dsize, inner_fport, inner_ptype[7:0], inner_ptype[15:8], src_mac[7:0], src_mac[15:8], src_mac[23:16], src_mac[31:24]};
								end
							end
							11'h02: begin // TX data write
								if (r_flow == 2'b10) begin
									{r_txc, r_txd}	<=	{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
								end else if(r_flow != 0) begin
									{r_txc, r_txd}	<=	{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff};
								end else begin
									//{r_txc, r_txd}	<=	{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, inner_daddr[7:0], inner_daddr[15:8], inner_daddr[23:16], inner_daddr[31:24]};
									{r_txc, r_txd}	<=	{inner_option[7:0], inner_option[15:8], inner_option[23:16], inner_option[31:24], inner_daddr[7:0], inner_daddr[15:8], inner_daddr[23:16], inner_daddr[31:24]};
								end
							end
							default: begin
								//{r_txc, r_txd}	<= {8'h00, w_dout[7:0], w_dout[15:8], w_dout[23:16], w_dout[31:24], w_dout[39:32], w_dout[47:40], w_dout[55:48], w_dout[63:56]};
								{r_txc, r_txd}	<= {8'h00, w_dout};
								if (r_tx_counter >= 14'd64) begin
									if (r_flow != 0 || w_aemp || r_tx_counter >= (MAX_SIZE-17) || r_tx_counter >= ((((inner_dsize+1) << 5)+32)-8)) begin
										r_tx_state	<=	FCS;
									end
								end 
							end
						endcase
					end
					FCS: begin
						//{r_txc, r_txd}	<=	{8'hf0, 32'h07_07_07_fd, w_crc_data[7:0], w_crc_data[15:8], w_crc_data[23:16], w_crc_data[31:24]};
						{r_txc, r_txd}	<=	{8'hf0, 32'h07_07_07_fd, w_crc_data[31:24], w_crc_data[23:16], w_crc_data[15:8], w_crc_data[7:0]};
						r_tx_state	<=	WGAP;
						r_crc_init	<=	1;
						r_tx_counter<=	0;
					end
					WGAP: begin
						{r_txc, r_txd}	<= {8'hff, 64'h07_07_07_07_07_07_07_07};
						if (r_tx_counter >= 6) begin
							r_tx_state		<=	WAIT;
							r_tx_counter	<=	0;
						end else begin
							r_tx_counter	<=	r_tx_counter + 1;
						end
					end
					endcase
				end
			end
		end else begin
			unimplement unimplement(); end // 未実装エラーを引き起こすための一文
	endgenerate

	fifo #(
		.BWIDTH(DATA_WIDTH),
		.DEPTH(MII_BUFLEN)
	) tx_buf (
		.wclk	(buf_clk),
		.rclk	(clk),
		.rst	(rst),

		.afull	(buf_full),
		.aemp	(w_aemp),
		.emp	(w_emp),

		.din_en	(buf_wen),
		.din	(buf_d),

		.dout_en(w_dout_en),
		.dout	(w_dout)
	);

	crc32 #(
		.DATA_WIDTH(DATA_WIDTH),
		.BIT_SWAP(1),
		.OUT_SWAP(1)
	) crc32_8 (
		.clk(~clk),
		.rst(rst|r_crc_init),
		.crc_en(w_crc_en),
		.data_in(w_crc_in),
		.crc_out(w_crc_data)
	);

endmodule