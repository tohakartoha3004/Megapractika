quit -sim

cd ../questasim

vlib work

# �������� �����
vlog -work work ../src/shift_register_32b.sv

vlog -work work ../src/packet_parser_2.sv


# ��������
vlog -work work ../tb/packet_parser_tb.sv



# ��������� ������
vsim -t 1ps -voptargs="+acc" +notimingchecks work.packet_parcer_tb -wlfdeleteonquit -onfinish stop

configure wave -timelineunits ns -signalnamewidth 1 


add wave -group env -radix hexadecimal packet_parcer_tb/*

add wave -group dut -radix hexadecimal packet_parcer_tb/dut/data_cnt

#add wave -divider "Dut"
#add wave -group dut -group ports -radix hexadecimal -ports    adder_axis_tb/dut/*
#add wave -group dut -group all   -radix hexadecimal -internal adder_axis_tb/dut/

run -all