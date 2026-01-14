`timescale 1ns / 1ps

module fifo #(
	parameter	BWIDTH	=	32,
	parameter	DEPTH	=	32
) (
	input					wclk,
	input					rclk,
	input					rst,

	output					full,
	output					emp,
	output					afull,	// almost full
	output					aemp, // almost empty

	input					din_en,
	input	[BWIDTH-1:0]	din,
	input					dout_en,
	output	[BWIDTH-1:0]	dout
);
	localparam	ADDR_WIDTH	=	$clog2(DEPTH);

	wire						wr_en;
	reg		[ADDR_WIDTH-1:0]	wr_addr;
	wire	[ADDR_WIDTH-1:0]	wr_addr1;

	wire						rd_en;
	reg		[ADDR_WIDTH-1:0]	rd_addr;

	wire						fifo_full;
	wire						fifo_emp;

	reg		[BWIDTH-1:0]		ram	[0:DEPTH-1];

	assign	wr_en	=	din_en  & ~fifo_full;
	assign	rd_en	=	dout_en & ~fifo_emp;

	always@(posedge wclk or posedge rst) begin
		if (rst) begin
			wr_addr			<= 0;
		end else begin
			if (wr_en == 1'b1) begin
				wr_addr			<=	wr_addr1;
				ram[wr_addr]	<=	din;
			end
		end
	end
	assign wr_addr1 = wr_addr + 1;

	always@(posedge rclk or posedge rst) begin
		if (rst) begin
			rd_addr			<= 0;
		end else begin
			if (rd_en == 1'b1) begin
				rd_addr			<=	rd_addr + 1;
			end
		end
	end

	assign	fifo_full	=	wr_addr1 == rd_addr;
	assign	fifo_emp	=	wr_addr == rd_addr;

	assign	full	=	fifo_full;
	assign	emp		=	fifo_emp;

	assign	afull	=	wr_addr-rd_addr >= {{(ADDR_WIDTH-1){1'b1}},1'b0};
	assign	aemp	=	wr_addr-rd_addr <= 1;

	assign	dout	=	(emp) ? {BWIDTH{1'b0}} : ram[rd_addr];

endmodule