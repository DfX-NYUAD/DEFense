set grp_cnt 0
set sec_insts [get_db insts .name *or1200_cpu_or1200_sprs_sr_reg_reg[0]*]

foreach a $sec_insts {set_db inst:$a .place_status fixed}

foreach a [get_db gui_rects -if {.gui_layer_name == *abcd || .gui_layer_name == *efgh}] {
	set loc_x [lindex [get_db $a .rect] 0 0]
	set loc_y [lindex [get_db $a .rect] 0 1]                                                                               
	set cbbx [get_db current_design .core_bbox]
	if {[expr $loc_x - 5] < [lindex $cbbx 0 0]} {set loc_x [expr [lindex $cbbx 0 0] + 5]}
	if {[expr $loc_y - 5] < [lindex $cbbx 0 1]} {set loc_y [expr [lindex $cbbx 0 1] + 5]}
	if {[expr $loc_x + 5] > [lindex $cbbx 0 2]} {set loc_x [expr [lindex $cbbx 0 2] - 5]}
	if {[expr $loc_y + 5] > [lindex $cbbx 0 3]} {set loc_y [expr [lindex $cbbx 0 3] - 5]}
	set insts [get_obj_in_area -area [expr $loc_x - 5] [expr $loc_y - 5] [expr $loc_x + 5] [expr $loc_y + 5] -obj_type inst]
        set total_area 0
	set new_lst ""
	for {set i 0} {$i < [llength $insts]} {incr i} {
                if {[lsearch -exact $sec_insts [get_db [lindex $insts $i] .name]] == -1} {
                        if {[llength [get_db [lindex $insts $i] .group]] == 0} {
                        set total_area [expr $total_area + [get_db [lindex $insts $i] .area]]
                        lappend new_lst [lindex $insts $i] 
                        }            
                } 	
	}
	set edge_val [expr [expr sqrt($total_area/0.85)]/2]
	set rect_val [expr $loc_x - $edge_val]    
	lappend rect_val [expr $loc_y - $edge_val]
	lappend rect_val [expr $loc_x + $edge_val]
	lappend rect_val [expr $loc_y + $edge_val]                             
	if {[llength $new_lst] > 1} {
		create_group -name group_count_${grp_cnt} -type guide -rects $rect_val
		update_group -name group_count_${grp_cnt} -add -objs [get_db $new_lst .name]
		incr grp_cnt
	}

#	if {[expr $loc_x - 20] < [lindex $cbbx 0 0]} {set loc_x [expr [lindex $cbbx 0 0] + 20]}
#        if {[expr $loc_y - 20] < [lindex $cbbx 0 1]} {set loc_y [expr [lindex $cbbx 0 1] + 20]}
#        if {[expr $loc_x + 20] > [lindex $cbbx 0 2]} {set loc_x [expr [lindex $cbbx 0 2] - 20]}
#        if {[expr $loc_y + 20] > [lindex $cbbx 0 3]} {set loc_y [expr [lindex $cbbx 0 3] - 20]}
#        set insts [get_obj_in_area -area [expr $loc_x - 20] [expr $loc_y - 20] [expr $loc_x + 20] [expr $loc_y + 20] -obj_type inst]
#        set total_area 0
#        set new_lst ""
#        for {set i 0} {$i < [llength $insts]} {incr i} {
#                if {[lsearch -exact $sec_insts [get_db [lindex $insts $i] .name]] == -1} {
#                        if {[llength [get_db [lindex $insts $i] .group]] == 0} {
#                        set total_area [expr $total_area + [get_db [lindex $insts $i] .area]]
#                        lappend new_lst [lindex $insts $i]
#                        }
#                }
#        }
#
#        set edge_val [expr [expr sqrt($total_area/0.85)]/2]
#        set rect_val [expr $loc_x - $edge_val]
#        lappend rect_val [expr $loc_y - $edge_val]
#        lappend rect_val [expr $loc_x + $edge_val]
#        lappend rect_val [expr $loc_y + $edge_val]
#        if {[llength $new_lst] > 1} {
#                create_group -name group_count_${grp_cnt} -type region -rects $rect_val
#                update_group -name group_count_${grp_cnt} -add -objs [get_db $new_lst .name]
#                incr grp_cnt
#        }
#proc checker_board_blkg {x1 y1 x2 y2 density} {
#	set init_y1 $y1
#	set x2_start 0
#	set y2_start 0
#	set i 0
#	while {$x2_start < $x2} {
#		set x2_start [expr $x1 + 2.5]
#		set j 0
#		while {$y2_start < $y2} {
#			set y2_start [expr $y2 + 2.5]
#			create_place_blockage -name checker_board_blkg_${i}_${j} -type partial -area "$x1 $y1 $x1_start $y1_start" -density $density
#			set y1 $y2_start
#			incr j
#		}
#		set x1 $x2_start
#		set y1 $init_y1
#		set y2 $init_y1
#		incr i
#	}
#}
}
	place_detail

delete_obj [get_db gui_rects -if {.gui_layer_name == *abcd*}]
delete_obj [get_db gui_rects -if {.gui_layer_name == *efgh*}]
