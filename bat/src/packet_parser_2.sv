// packet_parcer //
module packet_parser_2 (
    input wire clk,
    input wire reset,
    input wire [31:0] synch_ref, //etalonnoe znachenie synch//
// axi-stream slave//
    input wire [7:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,

    // AXI-Stream Master-vhod
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready,

    // flags identic
    output wire        is_synch,
    output wire        is_id,
    output wire        is_framesize,
    output wire        is_data,
    output wire        is_crc,

    // flags mistakes
    output wire        bad_synch,
    output wire        bad_framesize,
    output wire        bad_id,
    output wire        bad_crc
);

typedef enum reg [2:0] {
        IDLE,      // wait for new packet
        SYNCH,      
        ID,        
        LEN,       
        DATA,      
        CRC,       
        WAIT_EOP   // wait for signal tlast after CRC
    } state_t;

    reg state_current, state_next;
// regs and counts 
    reg [1:0]  byte_cnt;      // count byte in fixed fields (0..3)
    reg [7:0]  data_cnt;      // count arrived byte data (0..128)

    // regs for test
    reg [31:0] crc_sum;           
    reg [31:0] expected_len;   
    reg [31:0] last_id;       
    reg [31:0] expected_id;   

    // flags regs mistakes
    reg bad_synch_r;
    reg bad_id_r;
    reg bad_framesize_r;
    reg bad_crc_r;

// glass transmission
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tlast  = s_axis_tlast;
    assign s_axis_tready = m_axis_tready;

    wire handshake;
    assign handshake = s_axis_tvalid && s_axis_tready;

// signals is_ for work with handshakes and FSM
    assign is_synch     = (state_current == SYNCH) && handshake;
    assign is_id        = (state_current == ID)    && handshake;
    assign is_framesize = (state_current == LEN)   && handshake;
    assign is_data      = (state_current == DATA)  && handshake;
    assign is_crc       = (state_current == CRC)   && handshake;

// flags mistakes - vihod
    assign bad_synch     = bad_synch_r;
    assign bad_id        = bad_id_r;
    assign bad_framesize = bad_framesize_r;
    assign bad_crc       = bad_crc_r;

    // pisoedinenie modul k vsei work
    //obuvlenie signalov 
    wire shift_reg_en; //razreshenie sdviga
    wire [31:0] shift_reg_out; 

    shift_register_32b shift_reg_inst ( //prisvaivanie "vihododv"//
        .clk(clk),
        .reset(reset),
        .en(shift_reg_en),
        .din(s_axis_tdata),
        .dout(shift_reg_out)
    );
    //combinatornoe shift_reg_en=1 if handshake for one of state//
    assign shift_reg_en = handshake && (state_current == SYNCH ||
                                        state_current == ID    ||
                                        state_current == LEN   ||
                                        state_current == CRC);
// modul
always_comb begin
	state_next = state_current;
	case (state_current)
	 IDLE:    if (handshake) state_next = SYNCH;
	 SYNCH:   if (handshake && (byte_cnt == 2'd3)) state_next = ID;
	 ID:      if (handshake && (byte_cnt == 2'd3)) state_next = LEN;
	 LEN:     if (handshake && (byte_cnt == 2'd3)) state_next = DATA;
	 DATA:    if (handshake && (data_cnt == expected_len[7:0] - 1)) state_next = CRC;
	 CRC:     if (handshake && (byte_cnt == 2'd3)) state_next = WAIT_EOP;
	 WAIT_EOP: if (handshake && s_axis_tlast) state_next = IDLE;
	default: state_next = IDLE;
	endcase
  if (handshake && s_axis_tlast && (state_current != WAIT_EOP)) //vihod if tlast came early? than expected
  state_next = IDLE;
end

// obnovlenie regs
always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // reset regs to start position
            state_current    <= IDLE;
            byte_cnt         <= 2'b00;
            data_cnt         <= 8'b0;
            crc_sum          <= 32'b0;
            expected_len     <= 32'b0;
            last_id          <= 32'hFFFFFFFF; // -1, to first id: expected_id = 0
            expected_id      <= 32'b0;
            bad_synch_r      <= 1'b0;
            bad_id_r         <= 1'b0;
            bad_framesize_r  <= 1'b0;
            bad_crc_r        <= 1'b0;
        end else begin
            state_current <= state_next;

	if (handshake) begin
		if (state_current != DATA)
		byte_cnt <= byte_cnt +1; // obnovlenie count for SYNCH, ID, LEN, CRC
	
	case (state_current)
                    SYNCH: begin
                        // after 4 byte 
                        if (byte_cnt == 2'd3) begin
                            if (shift_reg_out != synch_ref)
                                bad_synch_r <= 1'b1;
                    end
		end
                    ID: begin
                        crc_sum <= crc_sum + {24'b0, s_axis_tdata};// rasshirenie 24->32
                        if (byte_cnt == 2'd3) begin
                            if (shift_reg_out != expected_id)//proverka
                                bad_id_r <= 1'b1;
                            else
                                last_id <= shift_reg_out;
                        end
                    end

                    LEN: begin
                        crc_sum <= crc_sum + {24'b0, s_axis_tdata};
                        if (byte_cnt == 2'd3) begin
                            expected_len <= shift_reg_out;
                            if (shift_reg_out < 32'd1 || shift_reg_out > 32'd128)//proverka diapazona 
                                bad_framesize_r <= 1'b1;
                        end
                    end

                    DATA: begin
                        data_cnt <= data_cnt + 1;
                        crc_sum <= crc_sum + {24'b0, s_axis_tdata};
                        if (s_axis_tlast) //tlast came earlier than packet end
                            bad_framesize_r <= 1'b1;
                    end

                    CRC: begin
                        if (byte_cnt == 2'd3) begin
                            if (shift_reg_out != crc_sum)
                                bad_crc_r <= 1'b1;
                        end
                    end

                    WAIT_EOP: ;
                    default: ;//proverka if state_current != case(...) 
                endcase
            end
 if (state_next == IDLE) begin //reset inside regs after end of packet
                byte_cnt         <= 2'b00;
                data_cnt         <= 8'b0;
                crc_sum          <= 32'b0;
                bad_synch_r      <= 1'b0;
                bad_id_r         <= 1'b0;
                bad_framesize_r  <= 1'b0;
                bad_crc_r        <= 1'b0;
            end
     
            expected_id <= last_id + 1; //new expected id for new test
        end
    end

endmodule