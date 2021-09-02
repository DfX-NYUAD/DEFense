set_multi_cpu_usage -local_cpu 16
source ./config.tcl

proc list_unique {list} {
    array set included_arr [list]
    set unique_list [list]
    foreach item $list {
        if { ![info exists included_arr($item)] } {
            set included_arr($item) ""
            lappend unique_list $item
        }
    }
    unset included_arr
    return $unique_list
}

set in_file      $env(OP_FILE)

set OUT_DIR ./out
# Reports and logs directories creation
file mkdir ${OUT_DIR}
set REPORTS_DIR "${OUT_DIR}/rpts"
set RESULTS_DIR "${OUT_DIR}/results"
set GDS_DIR     "${OUT_DIR}/gds"

file mkdir ${REPORTS_DIR}
file mkdir ${RESULTS_DIR}
file mkdir ${GDS_DIR}

# Initialize
set_db design_process_node 45
set TOP_DESIGN cep
set_db init_ground_nets VSS
set_db init_power_nets VDD
set setup_file out/cep_out/_genus_xfer.invs_setup.tcl

source $setup_file
update_rc_corner -name default_emulate_rc_corner -cap_table "/home/abc586/freepdk-45nm/rtk-typical.captable"

set_message -no_limit
set_interactive_constraint_modes default_emulate_constraint_mode
set_max_fanout 10 [get_db ports -if {.direction == *in}]
# Floorplan

create_floorplan -core_density_size 1.0 0.7 4.0 4.0 4.0 4.0

connect_global_net VDD -type pg_pin -pin_base_name VDD -inst_base_name * -verbose
connect_global_net VSS -type pg_pin -pin_base_name VSS -inst_base_name * -verbose

# Power Grid
route_special -nets {VDD VSS}
add_rings -nets {VDD VSS} -width 0.6 -spacing 0.5 -layer {top 7 bottom 7 left 6 right 6}

add_stripes -nets {VSS VDD} -layer 6 -direction vertical -width 0.4 -spacing 0.5 -set_to_set_distance 5 -start 0.5
add_stripes -nets {VSS VDD} -layer 7 -direction horizontal -width 0.4 -spacing 0.5 -set_to_set_distance 5 -start 0.5

# Place Ports

set_db assign_pins_edit_in_batch true

set ports [get_db ports .name]
edit_pin -fix_overlap 1 -unit MICRON -spread_direction clockwise -side Left -layer 3 -spread_type start -spacing 0.4 -start 0.0 2.0 -pin $ports

set_db assign_pins_edit_in_batch false

# Placement
#create_place_blockage -rects {4.18 1451.86 1514.68 1511.86} -type soft

proc checker_board_blkg {x1 y1 x2 y2 density} {
        set init_y1 $y1 
        set x2_start 0
        set y2_start 0
        set i 0
        while {$x2_start < $x2} {
                set x2_start [expr $x1 + 2.5]
                set j 0 
                while {$y2_start < $y2} {
                        set y2_start [expr $y1 + 2.5]
                        create_place_blockage -name checker_board_blkg_${i}_${j} -type partial -area "$x1 $y1 $x2_start $y2_start" -density $density
                        set y1 $y2_start
                        incr j
                }
                set x1 $x2_start
                set y1 $init_y1
                set y2_start $init_y1
                incr i
        }
}

checker_board_blkg 4.18 1411.86 1514.68 1511.86 20
checker_board_blkg 4.18 1361.86 1514.68 1411.86 50
checker_board_blkg 4.18 104.06 1514.68 154.06 50
checker_board_blkg 4.18 4.06 1514.68 104.06 20

foreach a [get_db pins .name *aes*key_reg*/Q] {
	foreach_in_collection b [all_fanout -from $a -only_cells] {set_db [get_db $b] .dont_touch true}
}

set_db [get_db nets *aes/key_big_*] .weight 10000

place_opt_design
source open_spaces_cep_flow_aes.tcl
source incr_density_cep.tcl

# CTS
set_db cts_target_max_transition_time 0.08
set_db cts_target_skew 0.5
set_db cts_update_clock_latency false
create_clock_tree -name clk -source wb_clk
ccopt_design
#write_db out/post_cts_aes_70.final

# Route

create_route_rule -name 2Wx1S -width {metal1:metal2 0.09 metal3:metal7 0.27} -spacing {metal1:metal7 0.07}

foreach a [get_db nets *aes/key_big_*] {
	set n_min_x [get_db current_design .core_bbox.dx]
	set n_min_y [get_db current_design .core_bbox.dy]
	set n_max_x 0
	set n_max_y 0
	set curr_rect [get_db $a .wires.rect.]
	for {set i 0} {$i < [llength $curr_rect]} {incr i} {
	        if {$n_min_x > [lindex $curr_rect $i 0]} {set n_min_x [lindex $curr_rect $i 0]}
	        if {$n_min_y > [lindex $curr_rect $i 1]} {set n_min_y [lindex $curr_rect $i 1]}
	        if {$n_max_x < [lindex $curr_rect $i 2]} {set n_max_x [lindex $curr_rect $i 2]}
	        if {$n_max_y < [lindex $curr_rect $i 3]} {set n_max_y [lindex $curr_rect $i 3]}
	}

set incr_nets [get_db [get_obj_in_area -obj_type net -area [expr $n_min_x - 5] [expr $n_min_y - 5] [expr $n_max_x + 5] [expr $n_max_y + 5]] .name]

set s_idx [lsearch $incr_nets [get_db $a .name]]
set incr_nets [lreplace $incr_nets $s_idx $s_idx]

set_db [get_db nets $incr_nets] .route_rule. 2Wx1S

foreach b $incr_nets {
        set_route_attributes -nets $b -route_rule 2Wx1S -bottom_preferred_routing_layer 3 -top_preferred_routing_layer 7 -preferred_routing_layer_effort high -route_rule_effort hard
}
	set_route_attributes -nets [get_db $a .name] -bottom_preferred_routing_layer 2 -top_preferred_routing_layer 3 -preferred_routing_layer_effort high -route_rule_effort hard
}



#set incr_nets [get_db [get_obj_in_area -obj_type net -area [expr $n_min_x - 5] [expr $n_min_y - 5] [expr $n_max_x + 5] [expr $n_max_y + 5]] .name]
#
#set s_idx [lsearch $incr_nets dft/next_out]
#set incr_nets [lreplace $incr_nets $s_idx $s_idx]
#
#set_db [get_db nets $incr_nets] .route_rule. 2Wx1S
#
#foreach a $incr_nets {
#        set_route_attributes -nets $a -route_rule 2Wx1S -bottom_preferred_routing_layer 3 -top_preferred_routing_layer 7 -preferred_routing_layer_effort high -route_rule_effort hard
#}

set_db route_design_strict_honor_route_rule true

route_design

set_db timing_analysis_type ocv
set_db opt_post_route_setup_recovery true
opt_design -post_route

set_db add_fillers_prefix FILL
set_db add_fillers_cells {FILLCELL_X4 FILLCELL_X2 FILLCELL_X1}
add_fillers

check_connectivity
check_drc

#write_netlist "${RESULTS_DIR}/${TOP_DESIGN}-post-par.v"

#Extract RC parameters file

#extract_rc
#write_parasitics -rc_corner default_emulate_rc_corner -spef_file "${RESULTS_DIR}/${TOP_DESIGN}-post-par.spef"

#Real Layout file
#write_stream ${OUT_DIR}/${GDS_DIR}/${TOP_DESIGN}-post-par.gds -merge "/home/abc586/freepdk-45nm/stdcells.gds" -map_file "/home/abc586/freepdk-45nm/rtk-stream-out.map"

write_db out/post_impl_cep_70_net_opt_aes.final

#Dump Delay Info reg2reg
#set fl [open ${REPORTS_DIR}/post_pnr_delay_reg2reg_info.csv w]
#set fl2 [open ${REPORTS_DIR}/post_pnr_reg2reg_features.csv w]
#puts $fl "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#set path_count 1
#foreach_in_collection path [report_timing -from [all_registers] -to [all_registers] -max_paths 10000 -collection] {
#	set launch [get_db $path .launching_point.name]
#	set capture [get_db $path .capturing_point.name]
#	set sum 0
#	foreach del [get_db $path .timing_points.delay] {set sum [expr $sum + $del]}
#	set depth [expr [llength [lsort -u [get_db $path .timing_points.pin.inst.name]]] - 2]
#	if {$depth < 0} {set depth 0}
#	puts $fl "$launch,$capture,$sum,$depth"
#	set loads [get_db [list_unique [get_db $path .timing_points.pin.net]] .capacitance_max]
#	set gates [get_db [get_db $path  .timing_points.pin. -if {.obj_type == *pin && .direction == *out}] .inst.base_cell.name]
#	set period [get_db $path .period],
#	set line_to_print ""
#	lappend line_to_print $path_count,
#	for {set i 1} {$i < [llength $loads]} {incr i} {
#		if {[regexp INV [lindex $gates [expr $i - 1]]]} {
#			set tmp_gate 1.0
#		} elseif {[regexp NAND [lindex $gates [expr $i - 1]]] || [regexp NOR [lindex $gates [expr $i - 1]]]} {
#			set tmp_gate 2.0
#		} elseif {[regexp AND [lindex $gates [expr $i - 1]]] || [regexp OR [lindex $gates [expr $i - 1]]]} {
#			set tmp_gate 3.0
#		} elseif {[regexp DFF [lindex $gates [expr $i - 1]]]} {set tmp_gate 5.0} else {set tmp_gate 4.0}
#			 lappend line_to_print $period,
#			 lappend line_to_print $tmp_gate,
#			 lappend line_to_print [lindex $loads $i],
#	}
#	puts $fl2 $line_to_print
#	incr path_count
#}
#close $fl
#close $fl2
#
##reg2out
#set fl [open ${REPORTS_DIR}/post_pnr_delay_reg2out_info.csv w]
#puts $fl "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#set fl2 [open ${REPORTS_DIR}/post_pnr_reg2out_features.csv w]
#set path_count 1
#foreach_in_collection path [report_timing -from [all_registers] -to [all_outputs] -max_paths 10000 -collection] {
#        set launch [get_db $path .launching_point.name]
#        set capture [get_db $path .capturing_point.name]
#        set sum 0
#        foreach del [get_db $path .timing_points.delay] {set sum [expr $sum + $del]}
#        set depth [expr [llength [lsort -u [get_db [get_db $path .timing_points.pin. -if {.obj_type == *pin}] .inst.name]]] - 2]
#        if {$depth < 0} {set depth 0}
#        puts $fl "$launch,$capture,$sum,$depth"
#        set loads [get_db [list_unique [get_db $path .timing_points.pin.net]] .capacitance_max]
#        set gates [get_db [get_db $path  .timing_points.pin. -if {.obj_type == *pin && .direction == *out}] .inst.base_cell.name]
#        set period [get_db $path .period],
#        set line_to_print ""
#        lappend line_to_print $path_count,
#        for {set i 1} {$i < [llength $loads]} {incr i} {
#                if {[regexp INV [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 1.0
#                } elseif {[regexp NAND [lindex $gates [expr $i - 1]]] || [regexp NOR [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 2.0
#                } elseif {[regexp AND [lindex $gates [expr $i - 1]]] || [regexp OR [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 3.0
#                } elseif {[regexp DFF [lindex $gates [expr $i - 1]]]} {set tmp_gate 5.0} else {set tmp_gate 4.0}
#                         lappend line_to_print $period,
#                         lappend line_to_print $tmp_gate,
#                         lappend line_to_print [lindex $loads $i],
#        }
#        puts $fl2 $line_to_print
#        incr path_count
#}
#close $fl
#close $fl2
#
## in2reg
#set fl [open ${REPORTS_DIR}/post_pnr_delay_in2reg_info.csv w]
#puts $fl "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#set path_count 1
#set fl2 [open ${REPORTS_DIR}/post_pnr_in2reg_features.csv w]
#foreach_in_collection path [report_timing -from [all_inputs] -to [all_registers] -max_paths 10000 -collection] {
#        set launch [get_db $path .launching_point.name]
#        set capture [get_db $path .capturing_point.name]
#        set sum 0
#        foreach del [get_db $path .timing_points.delay] {set sum [expr $sum + $del]}
#        set depth [expr [llength [lsort -u [get_db [get_db $path .timing_points.pin. -if {.obj_type == *pin}] .inst.name]]] - 1]        
#	if {$depth < 0} {set depth 0}
#        puts $fl "$launch,$capture,$sum,$depth"
#        set loads [get_db [list_unique [get_db $path .timing_points.pin.net]] .capacitance_max]
#        set gates [get_db [get_db $path  .timing_points.pin. -if {.obj_type == *pin && .direction == *out}] .inst.base_cell.name]
#        set period [get_db $path .period],
#	set line_to_print ""
#        lappend line_to_print $path_count,
#        for {set i 1} {$i < [llength $loads]} {incr i} {
#                if {[regexp INV [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 1.0
#                } elseif {[regexp NAND [lindex $gates [expr $i - 1]]] || [regexp NOR [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 2.0
#                } elseif {[regexp AND [lindex $gates [expr $i - 1]]] || [regexp OR [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 3.0
#                } elseif {[regexp DFF [lindex $gates [expr $i - 1]]]} {set tmp_gate 5.0} else {set tmp_gate 4.0}
#                         lappend line_to_print $period,
#                         lappend line_to_print $tmp_gate,
#                         lappend line_to_print [lindex $loads $i],
#        }
#        puts $fl2 $line_to_print
#        incr path_count
#}
#close $fl
#close $fl2
#
## in2out
#set fl [open ${REPORTS_DIR}/post_pnr_delay_in2out_info.csv w]
#puts $fl "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#set path_count 1
#set fl2 [open ${REPORTS_DIR}/post_pnr_in2out_features.csv w]
#foreach_in_collection path [report_timing -from [all_inputs] -to [all_outputs] -max_paths 10000 -collection] {
#        set launch [get_db $path .launching_point.name]
#        set capture [get_db $path .capturing_point.name]
#        set sum 0
#        foreach del [get_db $path .timing_points.delay] {set sum [expr $sum + $del]}
#        set depth [llength [lsort -u [get_db [get_db $path .timing_points.pin. -if {.obj_type == *pin}] inst.name]]]
#	if {$depth < 0} {set depth 0}
#        puts $fl "$launch,$capture,$sum,$depth"
#        set loads [get_db [list_unique [get_db $path .timing_points.pin.net]] .capacitance_max]
#        set gates [get_db [get_db $path  .timing_points.pin. -if {.obj_type == *pin && .direction == *out}] .inst.base_cell.name]
#        set period [get_db $path .period],
#	set line_to_print ""
#	lappend line_to_print $path_count,
#        for {set i 1} {$i < [llength $loads]} {incr i} {
#                if {[regexp INV [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 1.0
#                } elseif {[regexp NAND [lindex $gates [expr $i - 1]]] || [regexp NOR [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 2.0
#                } elseif {[regexp AND [lindex $gates [expr $i - 1]]] || [regexp OR [lindex $gates [expr $i - 1]]]} {
#                        set tmp_gate 3.0
#                } elseif {[regexp DFF [lindex $gates [expr $i - 1]]]} {set tmp_gate 5.0} else {set tmp_gate 4.0}
#                         lappend line_to_print $period,
#                         lappend line_to_print $tmp_gate,
#                         lappend line_to_print [lindex $loads $i],
#        }
#        puts $fl2 $line_to_print
#        incr path_count
#}
#close $fl
#close $fl2
#
#set fl1 [open syn_gen_reg2reg_paths.csv r]
#set lines1 [split [read $fl1] '\n']
#close $fl1
#
#set fl2 [open syn_gen_reg2reg_tmp.txt r]
#set lines2 [split [read $fl2] '\n']
#close $fl2
#
#set fl3 [open ${REPORTS_DIR}/syn_gen_reg2reg_timing_info.csv w]
#puts $fl3 "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#for {set i 0} {$i < [llength $lines1]} {incr i} {puts $fl3 "[lindex $lines1 $i 0][lindex $lines1 $i 1][lindex $lines2 $i],[lindex $lines1 $i 2]"}
#close $fl3
#
#set fl1 [open syn_gen_in2reg_paths.csv r]
#set lines1 [split [read $fl1] '\n']
#close $fl1
#
#set fl2 [open syn_gen_in2reg_tmp.txt r]
#set lines2 [split [read $fl2] '\n']
#close $fl2
#
#set fl3 [open ${REPORTS_DIR}/syn_gen_in2reg_timing_info.csv w]
#puts $fl3 "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#for {set i 0} {$i < [llength $lines1]} {incr i} {puts $fl3 "[lindex $lines1 $i 0][lindex $lines1 $i 1][lindex $lines2 $i],[lindex $lines1 $i 2]"}
#close $fl3
#
#set fl1 [open syn_gen_reg2out_paths.csv r]
#set lines1 [split [read $fl1] '\n']
#close $fl1
#
#set fl2 [open syn_gen_reg2out_tmp.txt r]
#set lines2 [split [read $fl2] '\n']
#close $fl2
#
#set fl3 [open ${REPORTS_DIR}/syn_gen_reg2out_timing_info.csv w]
#puts $fl3 "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#for {set i 0} {$i < [llength $lines1]} {incr i} {puts $fl3 "[lindex $lines1 $i 0][lindex $lines1 $i 1][lindex $lines2 $i],[lindex $lines1 $i 2]"}
#close $fl3
#
#set fl1 [open syn_gen_in2out_paths.csv r]
#set lines1 [split [read $fl1] '\n']
#close $fl1
#
#set fl2 [open syn_gen_in2out_tmp.txt r]
#set lines2 [split [read $fl2] '\n']
#close $fl2
#
#set fl3 [open ${REPORTS_DIR}/syn_gen_in2out_timing_info.csv w]
#puts $fl3 "Launch Point, Capturing point, Data Path Delay, Number of cominational cells in data path"
#for {set i 0} {$i < [llength $lines1]} {incr i} {puts $fl3 "[lindex $lines1 $i 0][lindex $lines1 $i 1][lindex $lines2 $i],[lindex $lines1 $i 2]"}
#close $fl3
#
#set fl [open syn_gen_reg2reg_gate_n_loads.txt r]
#set lines [split [read $fl] '\n']
#close $fl
#
#set cnt 1
#set line_to_print ""
#set fl [open ${REPORTS_DIR}/syn_gen_reg2reg_features.csv w]
#foreach a $lines {
#        if {[regexp Arrival $a]} {
#        	set period [expr [lindex $a 1]/1000]
#	        if {[llength $line_to_print] > 0} {puts $fl $line_to_print}
#        	set line_to_print ""
#	        lappend line_to_print $cnt
#        	incr cnt
#        }
#	if {[regexp unmapped_ $a] && [lindex $a 2] > 0} {
#        	if {[regexp not [lindex $a 1]]} {set tmp_gate 1.0}
#        	if {[regexp nand2 [lindex $a 1]] || [regexp nor2 [lindex $a 1]]} {set tmp_gate 2.0}
#        	if {[regexp _and2 [lindex $a 1]] || [regexp _or2 [lindex $a 1]]} {set tmp_gate 3.0}
#        	if {[regexp complex2 [lindex $a 1]]} {set tmp_gate 4.0}
#        	if {[regexp d_flop [lindex $a 1]]} {set tmp_gate 5.0}
#        	lappend line_to_print $period, 
#        	lappend line_to_print $tmp_gate,
#        	lappend line_to_print [lindex $a 2].
#        }
#}
#puts $fl $line_to_print
#close $fl
#
#set fl [open syn_gen_in2reg_gate_n_loads.txt r]
#set lines [split [read $fl] '\n']
#close $fl
#
#set cnt 1
#set line_to_print ""
#set fl [open ${REPORTS_DIR}/syn_gen_in2reg_features.csv w]
#foreach a $lines {
#        if {[regexp Arrival $a]} {
#                set period [expr [lindex $a 1]/1000]
#                if {[llength $line_to_print] > 0} {puts $fl $line_to_print}
#                set line_to_print ""
#                lappend line_to_print $cnt
#                incr cnt
#        }
#        if {[regexp unmapped_ $a] && [lindex $a 2] > 0} {
#                if {[regexp not [lindex $a 1]]} {set tmp_gate 1.0}
#                if {[regexp nand2 [lindex $a 1]] || [regexp nor2 [lindex $a 1]]} {set tmp_gate 2.0}
#                if {[regexp _and2 [lindex $a 1]] || [regexp _or2 [lindex $a 1]]} {set tmp_gate 3.0}
#                if {[regexp complex2 [lindex $a 1]]} {set tmp_gate 4.0}
#                if {[regexp d_flop [lindex $a 1]]} {set tmp_gate 5.0}
#                lappend line_to_print $period,
#                lappend line_to_print $tmp_gate,
#                lappend line_to_print [lindex $a 2].
#        }
#}
#puts $fl $line_to_print
#close $fl
#
#set fl [open syn_gen_reg2out_gate_n_loads.txt r]
#set lines [split [read $fl] '\n']
#close $fl
#
#set cnt 1
#set line_to_print ""
#set fl [open ${REPORTS_DIR}/syn_gen_reg2out_features.csv w]
#foreach a $lines {
#        if {[regexp Arrival $a]} {
#                set period [expr [lindex $a 1]/1000]
#                if {[llength $line_to_print] > 0} {puts $fl $line_to_print}
#                set line_to_print ""
#                lappend line_to_print $cnt
#                incr cnt
#        }
#        if {[regexp unmapped_ $a] && [lindex $a 2] > 0} {
#                if {[regexp not [lindex $a 1]]} {set tmp_gate 1.0}
#                if {[regexp nand2 [lindex $a 1]] || [regexp nor2 [lindex $a 1]]} {set tmp_gate 2.0}
#                if {[regexp _and2 [lindex $a 1]] || [regexp _or2 [lindex $a 1]]} {set tmp_gate 3.0}
#                if {[regexp complex2 [lindex $a 1]]} {set tmp_gate 4.0}
#                if {[regexp d_flop [lindex $a 1]]} {set tmp_gate 5.0}
#                lappend line_to_print $period,
#                lappend line_to_print $tmp_gate,
#                lappend line_to_print [lindex $a 2].
#        }
#}
#puts $fl $line_to_print
#close $fl
#
#set fl [open syn_gen_in2out_gate_n_loads.txt r]
#set lines [split [read $fl] '\n']
#close $fl
#
#set cnt 1
#set line_to_print ""
#set fl [open ${REPORTS_DIR}/syn_gen_in2out_features.csv w]
#foreach a $lines {
#        if {[regexp Arrival $a]} {
#                set period [expr [lindex $a 1]/1000]
#                if {[llength $line_to_print] > 0} {puts $fl $line_to_print}
#                set line_to_print ""
#                lappend line_to_print $cnt
#                incr cnt
#        }
#        if {[regexp unmapped_ $a] && [lindex $a 2] > 0} {
#                if {[regexp not [lindex $a 1]]} {set tmp_gate 1.0}
#                if {[regexp nand2 [lindex $a 1]] || [regexp nor2 [lindex $a 1]]} {set tmp_gate 2.0}
#                if {[regexp _and2 [lindex $a 1]] || [regexp _or2 [lindex $a 1]]} {set tmp_gate 3.0}
#                if {[regexp complex2 [lindex $a 1]]} {set tmp_gate 4.0}
#                if {[regexp d_flop [lindex $a 1]]} {set tmp_gate 5.0}
#                lappend line_to_print $period,
#                lappend line_to_print $tmp_gate,
#                lappend line_to_print [lindex $a 2].
#        }
#}
#puts $fl $line_to_print
#close $fl
#
#rm syn_gen_*summary.txt
#rm syn_gen_*paths.csv
#rm syn_gen_*tmp.txt
#rm syn_gen_*gate_n_loads.txt
#
##Report timing
#report_timing > ${REPORTS_DIR}/timing.rpt
exit
