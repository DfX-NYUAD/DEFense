set fl [open trigger_space_or1200.rpt w]

set site_matrix ""
set tmp ""
set open_locs_x ""
#delete_filler
delete_obj [get_db gui_rects -if {.gui_layer_name == *abcd*}]
delete_obj [get_db gui_rects -if {.gui_layer_name == *efgh*}]

set max_x 0
set min_x [get_db current_design .bbox.dx]
foreach a [get_db insts *or1200_cpu_or1200_sprs_sr_reg_reg[0]*] {
        if {[lindex [get_db $a .location] 0 0] < $min_x} {set min_x [lindex [get_db $a .location] 0 0]}
        if {[lindex [get_db $a .location] 0 0] > $max_x} {set max_x [lindex [get_db $a .location] 0 0]}
}
set min_x [expr $min_x - 100]
set max_x [expr $max_x + 100]


set key_rows "" 
foreach a [get_db insts *or1200_cpu_or1200_sprs_sr_reg_reg[0]*] {      
	set c_x [lindex [get_db $a .location] 0 0]
	set c_y [lindex [get_db $a .location] 0 1]
	lappend key_rows [get_obj_in_area -area [expr $c_x - 100] [expr $c_y - 100] [expr $c_x + 100] [expr $c_y + 100] -obj_type row]
}
set key_rows [lsort -u $key_rows]  
set key_rows_rect [get_db $key_rows .rect]

set rows_rect [get_db current_design .rows.rect.]
set sites_x [lindex [get_db sites .size] 0 0]
set sites_y [lindex [get_db sites .size] 0 1]
puts $fl "Empty Sites Per Row:"
puts $fl "Row Number\tNumber of Sites"
for {set i 0} {$i < [llength $rows_rect]} {incr i} {
	set curr_row [lindex $rows_rect $i]
	set curr_row_sites ""
	set start_x [lindex $curr_row 0]
	set end_x [lindex $curr_row 2]
	set low_y [lindex $curr_row 1]
	set high_y [lindex $curr_row 3]
	set open_count 0
	set curr_x $start_x
	for {set j $start_x} {$j < $end_x} {set j [expr $j + $sites_x]} {
		set next_x [expr $curr_x + $sites_x]
		set site_cell [get_obj_in_area -area [expr $curr_x + 0.1] [expr $low_y + 0.1] [expr $next_x - 0.1] [expr $high_y - 0.1] -obj_type inst]
		if {[llength $site_cell] == 0 || [regexp FILL $site_cell]} {
			if {[lsearch $key_rows_rect [lindex $rows_rect $i]] != -1} {
                              if {$curr_x > $min_x && $next_x < $max_x} {		
				incr open_count
				set tmp $curr_x
				lappend tmp $low_y
				lappend tmp $next_x
				lappend tmp $high_y
				lappend open_locs_x $tmp
				lappend curr_row_sites 1
				} else {lappend curr_row_sites 0}
			} else {
				lappend curr_row_sites 0
			}
		} else {
			lappend curr_row_sites 0
		}
		set curr_x $next_x
	}
	puts $fl "$i\t\t$open_count"
	lappend site_matrix $curr_row_sites
}
puts $fl "\n"	

array unset island_x_info
set island_x_count 0
set start_p 0
set end_p 0
for {set i 0} {$i < [llength $open_locs_x]} {incr i} {
	set adj_count 0
	set sites_in_island ""
	while {[lindex $open_locs_x $i 2] == [lindex $open_locs_x [expr $i + 1] 0]}  {
		if {$adj_count == 0} {
			set start_p [lindex $open_locs_x $i]
			lappend sites_in_island $i
		}           
		incr adj_count
		incr i
		set end_p [lindex $open_locs_x $i]
		lappend sites_in_island $i
	}
	incr adj_count                                               
#	if {$adj_count > 5} {puts $fl "$start_p -- $end_p -- $adj_count"}
	lappend island_x_info($island_x_count) $adj_count
	lappend island_x_info($island_x_count) $start_p
	lappend island_x_info($island_x_count) $end_p
	lappend island_x_info($island_x_count) $sites_in_island
	incr island_x_count
}
set connected_space_count 0
array unset connected_spaces
set open_locs_y $open_locs_x
for {set i 0} {$i < $island_x_count} {incr i} {
	set sp [lindex $island_x_info($i) 1]
	set ep [lindex $island_x_info($i) 2]
	set tmp_rect [lindex $sp 0]
	lappend tmp_rect [expr [lindex $sp 1] + $sites_y]
	lappend tmp_rect [lindex $sp 2]
	lappend tmp_rect [expr [lindex $sp 3] + $sites_y]
	set new_rect $tmp_rect
	if {[lsearch $open_locs_y $new_rect] > -1} {
		set pos [lsearch $open_locs_y $new_rect]
		for {set j 0} {$j < $island_x_count} {incr j} {                                        
			set new_ep [lsearch [lindex $island_x_info($j) 3] $pos]   
			if {$new_ep > -1} {                                
				set connected_spaces($connected_space_count) $i    
				lappend connected_spaces($connected_space_count) $j     
				incr connected_space_count
			}
		}
	} else {
		set new_rect [lreplace $new_rect 0 0 [lindex $ep 0]]
		set new_rect [lreplace $new_rect 2 2 [lindex $ep 2]]
		if {[lsearch $open_locs_y $new_rect] > -1} { 
                	set pos [lsearch $open_locs_y $new_rect]
                	for {set j 0} {$j < $island_x_count} {incr j} {        
                		set new_ep [lsearch [lindex $island_x_info($j) 3] $pos]   
                	        if {$new_ep > -1} {                                
                	                set connected_spaces($connected_space_count) $i          
                	                lappend connected_spaces($connected_space_count) $j
                	                incr connected_space_count
                	        }
                	}
        	}	
	}
}
set threshold 20

array unset connected_spaces_final
set connected_spaces_count_final 0

for {set i 0} {$i < $connected_space_count} {incr i} {
	set flag 0
	for {set j 0} {$j < $connected_space_count} {incr j} {
		if {[lsearch $connected_spaces($j) [lindex $connected_spaces($i) 0]] > -1} {
			lappend connected_spaces_final($connected_spaces_count_final) [lindex $connected_spaces($i) 0]
			lappend connected_spaces_final($connected_spaces_count_final) [lindex $connected_spaces($i) 1]
			foreach w $connected_spaces($j) {
				lappend connected_spaces_final($connected_spaces_count_final) $w
				for {set k 0} {$k < $connected_space_count} {incr k} {
					if {[lsearch $connected_spaces($k) $w] > -1} {
						foreach q $connected_spaces($k) {lappend connected_spaces_final($connected_spaces_count_final) $q}
					}
				}
			}			
		}
		if {[lsearch $connected_spaces($j) [lindex $connected_spaces($i) 1]] > -1} {
			lappend connected_spaces_final($connected_spaces_count_final) [lindex $connected_spaces($i) $k]
			foreach w $connected_spaces($j) {
				lappend connected_spaces_final($connected_spaces_count_final) $w
				for {set k 0} {$k < $connected_space_count} {incr k} {
					if {[lsearch $connected_spaces($k) $w] > -1} {
						foreach q $connected_spaces($k) {lappend connected_spaces_final($connected_spaces_count_final) $q}
					}
				}
			}
		set flag 1
		}
	}
	if {$flag == 1} {
		set connected_spaces_final($connected_spaces_count_final) [lreplace [lsort -u $connected_spaces_final($connected_spaces_count_final)] 0 0]
		incr connected_spaces_count_final
	}
}

set unique_conn_count 1
array unset unique_conn

set unique_conn(0) $connected_spaces_final(0)
for {set i 0} {$i < $connected_spaces_count_final} {incr i} {
	set flag 0
	for {set j 0} {$j < $i} {incr j} {
		if {[regexp $connected_spaces_final($j) $connected_spaces_final($i)]} {set flag 0;break} else {set flag 1}
	}
	if {$flag == 1} {set unique_conn($unique_conn_count) $connected_spaces_final($i); incr unique_conn_count}
}

set unique_flat ""
set merged_final ""
for {set i 0} {$i < $unique_conn_count} {incr i} {lappend unique_flat $unique_conn($i)}

for {set i 0} {$i < [llength $unique_flat]} {incr i} {
	set conn_u [lindex $unique_flat $i]
	foreach a $unique_flat {
		foreach b $a {
			if {[lsearch [lindex $unique_flat $i] $b] > -1} {lappend conn_u $a}
		}
	}
	set conn_u_final ""
	foreach c $conn_u {
		if {[llength $c] == 1} {
		lappend conn_u_final $c
		} else {
			foreach d $c {lappend conn_u_final $d}
		}
	}
	lappend merged_final [lsort -r -u $conn_u_final]
}

array unset unique_merged_conn
set merged_conn_count 1
set unique_merged_conn(0) [lindex $merged_final 0]

for {set i 0} {$i < $unique_conn_count} {incr i} {
        set flag 0
        for {set j 0} {$j < $i} {incr j} {
		if {[regexp [lindex $merged_final $j] [lindex $merged_final $i]]} {set flag 0;break} else {set flag 1}
	}
	if {$flag == 1} {set unique_merged_conn($merged_conn_count) [lindex $merged_final $i]; incr merged_conn_count}
}

array unset layer_info
set max_signal_routing_layer 7

puts $fl "Number of Routes in region:"
set num_count 0
set final_island_count 0
for {set i 0} {$i < $merged_conn_count} {incr i} {
	set site_islands ""
	set tmp_var ""
	foreach a $unique_merged_conn($i) {
		lappend tmp_var $a
		set tmp_var [lsort -r -u $tmp_var]
		foreach b [lindex $island_x_info($a) 3] {lappend site_islands $b}
	}
	if {[llength $site_islands] > $threshold} {
                 foreach q [get_db layers -if {.type == *routing}] { 
                                if {[get_db $q .direction] == "horizontal"} {set layer_pitch [get_db $q .pitch_y];set num_routes [expr $sites_y/$layer_pitch]}
                                if {[get_db $q .direction] == "vertical"} {set layer_pitch [get_db $q .pitch_x];set num_routes [expr $sites_x/$layer_pitch]}  
                                if {[get_db $q .route_index] < 7} {set layer_info([get_db $q .name]) $num_routes;set layer_count([get_db $q .name]) 0}
                }
		foreach c $site_islands {
			incr num_count
			set routes [get_obj_in_area -area [lindex $open_locs_x $c] -obj_type {wire special_wire}]
			set filt_route [get_db $routes -if {.layer.route_index < 7}]
			foreach w [get_db $filt_route .layer] {
				if {[get_db $w .route_index] == 1} {incr layer_count([get_db $w .name])}
				if {[get_db $w .route_index] == 2} {incr layer_count([get_db $w .name])}
				if {[get_db $w .route_index] == 3} {incr layer_count([get_db $w .name])}
				if {[get_db $w .route_index] == 4} {incr layer_count([get_db $w .name])}
				if {[get_db $w .route_index] == 5} {incr layer_count([get_db $w .name])}
				if {[get_db $w .route_index] == 6} {incr layer_count([get_db $w .name])}
			}
			
		
				set route_util_2 [expr $layer_count(metal2)/[expr floor([expr $layer_info(metal2)*[llength $site_islands]])]]
				set route_util_3 [expr $layer_count(metal2)/[expr floor([expr $layer_info(metal2)*[llength $site_islands]])]]
				if {$route_util_2 < 0.6 || $route_util_3 < 0.6} {create_gui_shape -layer abcd -rect [lindex $open_locs_x $c]} else {create_gui_shape -layer efgh -rect [lindex $open_locs_x $c]}

			if {$c == [lindex $site_islands end end]} {
				incr final_island_count
				puts $fl "Open Region $final_island_count:"
				puts $fl "Metal 1 - $layer_count(metal1)/[expr floor([expr $layer_info(metal1)*[llength $site_islands]])], Metal 2 - $layer_count(metal2)/[expr floor([expr $layer_info(metal2)*[llength $site_islands]])], Metal 3 - $layer_count(metal3)/[expr floor([expr $layer_info(metal3)*[llength $site_islands]])], Metal 4 - $layer_count(metal4)/[expr floor([expr $layer_info(metal4)*[llength $site_islands]])], Metal 5 - $layer_count(metal5)/[expr floor([expr $layer_info(metal5)*[llength $site_islands]])], Metal 6 - $layer_count(metal6)/[expr floor([expr $layer_info(metal6)*[llength $site_islands]])]"; puts $fl "Number of sites: [llength $site_islands]\n\n"}
		}
	}
}

for {set i 0} {$i < $island_x_count} {incr i} {
	if {[lsearch $tmp_var $i] == -1} {
		if {[llength [lindex $island_x_info($i) 3]] > $threshold} {
			incr final_island_count
			foreach c [lindex $island_x_info($i) 3] {
				create_gui_shape -layer abcd -rect [lindex $open_locs_x $c]
				incr num_count
			}
		}
	}
}

puts $fl "Final Number of continous possible Trojan insertion locations: $final_island_count"
close $fl
