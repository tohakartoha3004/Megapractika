`timescale 1ns/1ps

module packet_parcer_tb ();

  `include "axis_vip.vh"
  `include "tb_defines.vh"
  `include "tb_plusargs.vh"
  `include "tb_tasks.vh"



  localparam int AXIS_WIDTH = 8;

  reg clk = 0;
  reg reset = 1;

  reg  [31:0] synch_ref;

  reg  [7:0]  s_axis_tdata;
  reg         s_axis_tvalid;
  reg         s_axis_tlast;
  wire        s_axis_tready;

  wire [7:0]  m_axis_tdata;
  wire        m_axis_tvalid;
  wire        m_axis_tlast;
  reg         m_axis_tready;

  wire is_synch;
  wire is_id;
  wire is_framesize;
  wire is_data;
  wire is_crc;

  wire bad_synch;
  wire bad_framesize;
  wire bad_id;
  wire bad_crc;

  reg [7:0] axis_in_bytes  [0:`MAX_TRANS_NUMBER];
  reg [7:0] axis_out_bytes [0:`MAX_TRANS_NUMBER];

  reg       axis_out_is_synch     [0:`MAX_TRANS_NUMBER];
  reg       axis_out_is_id        [0:`MAX_TRANS_NUMBER];
  reg       axis_out_is_framesize [0:`MAX_TRANS_NUMBER];
  reg       axis_out_is_data      [0:`MAX_TRANS_NUMBER];
  reg       axis_out_is_crc       [0:`MAX_TRANS_NUMBER];

  reg       axis_out_bad_synch     [0:`MAX_TRANS_NUMBER];
  reg       axis_out_bad_framesize [0:`MAX_TRANS_NUMBER];
  reg       axis_out_bad_id        [0:`MAX_TRANS_NUMBER];
  reg       axis_out_bad_crc       [0:`MAX_TRANS_NUMBER];

  integer unsigned axis_in_cnt = 0;
  integer unsigned axis_out_cnt = 0;
  integer unsigned trans_cnt = 0;

  event data_i_e, data_o_e;

  reg error_flag = 1'b0;

  byte unsigned new_packet_axis[];

  packet_parser_2 dut (
    .clk           (clk),
    .reset         (reset),
    .synch_ref     (synch_ref),
    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tlast  (s_axis_tlast),
    .s_axis_tready (s_axis_tready),
    .m_axis_tdata  (m_axis_tdata ),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tlast  (m_axis_tlast ),
    .m_axis_tready (m_axis_tready),
    .is_synch      (is_synch),
    .is_id         (is_id),
    .is_framesize  (is_framesize),
    .is_data       (is_data),
    .is_crc        (is_crc),
    .bad_synch     (bad_synch),
    .bad_framesize (bad_framesize),
    .bad_id        (bad_id),
    .bad_crc       (bad_crc)
  );

  always #5 clk = ~clk;

  initial begin
    s_axis_tdata  = 8'h00;
    s_axis_tvalid = 1'b0;
    s_axis_tlast  = 1'b0;
    m_axis_tready = 1'b1;
    synch_ref     = 32'hA1B1C2D4;
  end

  initial begin
    get_plusargs();
    repeat (10) @(posedge clk);
    reset <= 0;
  end

  initial begin

    make_packet(10, new_packet_axis);

    $display("%0d", $size(new_packet_axis));
    foreach(new_packet_axis[i]) $display("packet = %0d", new_packet_axis[i]);

    fork
      // --------- drivers --------

      `AXIS_SLAVE_DRIVER(clk, s_axis_tready, s_axis_tdata, s_axis_tvalid, min_axis_delay, max_axis_delay, max_axis_value, seed)

      `AXIS_MASTER_DRIVER(clk, m_axis_tready, min_axis_delay, max_axis_delay, seed)

      // -------- monitors --------
      `AXIS_MONITOR(clk, s_axis_tvalid, s_axis_tready, data_i_e)

      `AXIS_MONITOR(clk, m_axis_tvalid, m_axis_tready, data_o_e)

      // -------- scoreboard ---------

      while (1) begin
        @(data_i_e);
        axis_in_bytes[axis_in_cnt] = s_axis_tdata;
        axis_in_cnt = axis_in_cnt + 1;
      end

      while (1) begin
        @(data_o_e);
        axis_out_bytes[axis_out_cnt] = m_axis_tdata;
        axis_out_is_synch[axis_out_cnt]     = is_synch;
        axis_out_is_id[axis_out_cnt]        = is_id;
        axis_out_is_framesize[axis_out_cnt] = is_framesize;
        axis_out_is_data[axis_out_cnt]      = is_data;
        axis_out_is_crc[axis_out_cnt]       = is_crc;

        axis_out_bad_synch[axis_out_cnt]     = bad_synch;
        axis_out_bad_framesize[axis_out_cnt] = bad_framesize;
        axis_out_bad_id[axis_out_cnt]        = bad_id;
        axis_out_bad_crc[axis_out_cnt]       = bad_crc;

        axis_out_cnt = axis_out_cnt + 1;
      end

      while (1) begin
        @(data_o_e);
        if (axis_in_bytes[trans_cnt] !== axis_out_bytes[trans_cnt]) begin
          $display("ERROR! Byte mismatch at index %0d: in=0x%02h out=0x%02h time=%0t", trans_cnt, axis_in_bytes[trans_cnt], axis_out_bytes[trans_cnt], $time);
          error_flag = 1'b1;
        end

        if (!(axis_out_is_synch[trans_cnt] || axis_out_is_id[trans_cnt] || axis_out_is_framesize[trans_cnt] || axis_out_is_data[trans_cnt] || axis_out_is_crc[trans_cnt])) begin
          //$display("WARNING: DUT did not mark any field for output byte index %0d value 0x%02h time=%0t", trans_cnt, axis_out_bytes[trans_cnt], $time);
        end

        trans_cnt = trans_cnt + 1;

        check_finish(trans_cnt, trans_number, error_flag);
      end
    join
  end

  initial begin
    $dumpfile("packet_parcer_tb.vcd");
    $dumpvars(0, packet_parcer_tb);
  end

  initial begin
    # (max_clk_in_test * 10);
    $display("ERROR! Watchdog timeout!");
    $display("----------------------");
    $display("---- TEST FAILED! ----");
    $display("----------------------");
    $finish;
  end

  function automatic void make_packet(int size, ref byte unsigned packet[]); 

    byte unsigned new_packet [$];
    int i; 
    for (i = 0; i < size; i++) begin
      new_packet.push_front(i);
    end  
    packet = new_packet;
   
  endfunction




endmodule

