module shift_register_32b (
    input wire        clk,
    input wire        reset,
    input wire        en,          // sdvinut if handshake
    input wire [7:0]  din,         // vhod byte
    output reg [31:0] dout         //vihod reg 32 bit
);
    always_ff @(posedge clk or posedge reset) begin //po front clk and rst
        if (reset) //rst=1
            dout <= 32'b0; //output = 0
        else if (en)
            dout <= {dout[23:0], din};  // v mladshie razrud sdvigaem new bit
    end
endmodule
