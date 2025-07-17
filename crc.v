`timescale 1ns / 1ps

module crc32# (
	parameter DATA_WIDTH = 8,
	parameter BIT_SWAP = 1,
	parameter OUT_SWAP = 1,
	parameter OUTPUT_EXOR = 32'hFFFFFFFF
) (
	input clk,
	input rst,
	input crc_en,
	input [DATA_WIDTH-1:0] data_in,
	output [31:0] crc_out
);
	reg [31:0] crc_reg;

	parameter	POLYNOMIAL = 32'h04C11DB7;

	wire	[DATA_WIDTH-1:0] in_data;
	generate
		if (BIT_SWAP) begin
			genvar i;
			for(i = 0; i < DATA_WIDTH; i = i + 1) begin
				assign in_data[i] = data_in[DATA_WIDTH-1-i];
			end
		end else begin
			assign in_data = data_in;
		end
	endgenerate

	/* CRC calc */
	function [31:0] crc_calc;
		input [31:0] in_crc;
		input in_data;
		integer i;
	begin
		for (i = 0; i < 32; i = i + 1) begin
			crc_calc[i] = 1'b0;
			if (i != 0)
				crc_calc[i] = in_crc[i-1];
			if (POLYNOMIAL[i])
				crc_calc[i] = crc_calc[i] ^ in_crc[31] ^ in_data;
		end
	end
	endfunction

	/* CRC calc loop */
	function [31:0] crc_calc_l;
		input [31:0] in_crc;
		input [DATA_WIDTH-1:0] in_data;
		integer i;
	begin
		crc_calc_l = in_crc;
		for (i = 0; i < DATA_WIDTH; i = i + 1) begin
			crc_calc_l = crc_calc(crc_calc_l, in_data[(DATA_WIDTH-1)-i]);
		end
	end
	endfunction

	/* CRC register */
	wire	[31:0]	a = crc_calc_l(crc_reg, in_data);
	always @(posedge clk, posedge rst) begin: crc_reg_l
		if (rst)
			crc_reg <= 32'hFFFFFFFF;
		else begin
			crc_reg <= crc_en ? a : crc_reg;
		end
	end

	generate
		genvar i;
		if (OUT_SWAP) begin
			for(i = 0; i < 32; i = i + 1) begin
				assign crc_out[i] = crc_reg[31-i] ^ OUTPUT_EXOR[i];
			end
		end else begin
			assign crc_out = crc_reg ^ OUTPUT_EXOR;
		end
	endgenerate
endmodule
