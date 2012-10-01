# statusIndicator.tcl : MD status/progressindicator VMD plugin
# Author: Dan Michael O. Heggø <danmichaelo _at_ gmail.com>
#
#   Implements a customizable progress indicator showing the timestep and custom information
# 
#   > package require statusindicator
#   > statusindicator -progress on -timestep 0.0001 -header "Hello world"
#
#   To update the header, you may use
#
#   > set ::statusIndicator::header "Text"
#
#   A simple GUI is available. To add a menu item to the Extensions menu:
# 
#   > vmd_install_extension statusIndicator statusIndicator_tk "Status indicator"
#
# Installation:
#
#   Put the statusIndicator folder in a folder searched by VMD, that is, a folder listed 
#   in auto_path. For instance, you may put it in ~/vmd/plugins, and add
#       set auto_path [concat $env(HOME)/vmd/plugins $auto_path] ;
#   to your ~/.vmdrc file. To add the plugin to the Plugins-menu, add the following to 
#   your ~/.vmdrc file (or just type it in VMD when needed):
#       vmd_install_extension statusIndicator statusIndicator_tk "Status indicator"
#

package provide statusIndicator 1.1

#########################################
# statusindicator [on|off] [timestep]
#
#     Displays a dynamic progress indicator for the top molecule.
#     Timestep per frame can be given in picoseconds. Defaults to 0.001.
#
# Examples:
#
#     >>> statusindicator -progress on -timestep 0.004
#     >>> statusindicator -header "Temperature: 1000 K"
#
proc statusindicator {args} {

    if { [llength $args] == 0 } {
        puts "usage: statusindicator -progress \[on|off\] -timestep \[timestep\] -header \[string\]"
        puts "Displays a dynamic progress indicator for the top molecule."
        puts "Timestep per frame can be given in picoseconds. Defaults to 0.001."
        return
    }
  
    # Parse options
    for { set argnum 0 } { $argnum < [llength $args] } { incr argnum } {
        set arg [ lindex $args $argnum ]
        set val [ lindex $args [expr $argnum + 1]]
        # DEBUG: puts "OPTION: $arg $val"
        switch -- $arg {
            "-progress" {             
                if { $val=="on" && !$::statusIndicator::timeline_on } {
                    set ::statusIndicator::timeline_on 1
                    set ::statusIndicator::timeline_checked 1
                    ::statusIndicator::toggled
                } elseif { $val=="off" && $::statusIndicator::timeline_on } {
                    set ::statusIndicator::timeline_on 0
                    set ::statusIndicator::timeline_checked 0    
                    ::statusIndicator::toggled  
                }
                incr argnum
            }
            "-timestep" {
                if { [string is double $val] } { 
                    puts "Setting timestep to $val ps"
                    set ::statusIndicator::timestep [expr double($val)]
                }
                incr argnum
            }
            "-header" {
                set ::statusIndicator::header $val            
                incr argnum
             }
            default { error "Warning: statusindicator got unknown option: $arg" }
        }
    }
}  

namespace eval ::statusIndicator:: {
    set statusIndicator_scale    1.  ;# actual scale of the top molecule
    set statusIndicator_mol     -1   ;# mol in which the drawing is done
    
    set display_width  1.  ;# max x in OpenGL
    set display_height 1.  ;# max y in OpenGL  
    set display_front  1.  ;# max z in OpenGL  
  
    set timestep 0.001     ;# 0.0001 ps per frame
    set timeline_checked 0 ;# disable
    set timeline_on 0      ;# disable
    set header ""          ;# blank
    set unit "ps"          ;# picoseconds
  
    set statusIndicator_color    black  ;# use a dark foreground color? 
    set statusIndicator_inversecolor    blue  ;# use a dark foreground color? 
    set statusIndicator_state    off
    
    set percentage 0.0
    set timeLabel ""
    set error_msg ""       ;# for GUI
    
    set debug_enabled 0
  
    #gui
    variable w             ;# handle to main window
  
}

proc ::statusIndicator::debug {msg} {
    variable debug_enabled
    if {$debug_enabled} { puts "\[statusIndicator\]: $str" }
}

proc ::statusIndicator::enable {} {
    variable statusIndicator_mol
    global vmd_frame
    global vmd_quit

    if ![catch {molinfo $statusIndicator_mol get name}] {return}
  
    set top [molinfo top]
    set statusIndicator_mol [mol new]
    mol rename $statusIndicator_mol "statusIndicator"
    if {$top >= 0} {
        mol top $top
        molinfo $statusIndicator_mol set scale_matrix [molinfo $top get scale_matrix]  
    }
  
    reset_colors  
  
    trace add variable ::vmd_logfile write ::statusIndicator::frame_changed
    trace add variable vmd_frame write ::statusIndicator::frame_changed
    trace add variable vmd_quit write ::statusIndicator::on_vmd_quit
    trace add variable ::statusIndicator::timestep write ::statusIndicator::timestep_changed
    trace add variable ::statusIndicator::header write ::statusIndicator::timestep_changed
    trace add variable ::statusIndicator::unit write ::statusIndicator::timestep_changed
}

proc ::statusIndicator::disable {cleanup} {
    variable statusIndicator_mol

    trace remove variable ::vmd_logfile write ::statusIndicator::frame_changed
    trace remove variable vmd_frame write ::statusIndicator::frame_changed
    trace remove variable ::vmd_quit write ::statusIndicator::on_vmd_quit
    trace remove variable ::statusIndicator::timestep write ::statusIndicator::timestep_changed
    trace remove variable ::statusIndicator::header write ::statusIndicator::timestep_changed
    trace remove variable ::statusIndicator::unit write ::statusIndicator::timestep_changed

    if {$cleanup == 1} {
        catch {mol delete $statusIndicator_mol}
    }
}

proc ::statusIndicator::on_vmd_quit { args } {
    puts "statusIndicator plugin info) Got vmd_quit event"
    disable 0
}

proc ::statusIndicator::reset_colors {} {
    variable statusIndicator_color
    if [display get backgroundgradient] {
        set backlight [eval vecadd [colorinfo rgb [color Display BackgroundBot]]]
    } else {
        set backlight [eval vecadd [colorinfo rgb [color Display Background]]]
    }
    if {$backlight <= 1.2} {
        set statusIndicator_color white
    } else {
        set statusIndicator_color black
    }
}

proc ::statusIndicator::redraw {} {
    variable statusIndicator_mol
    variable statusIndicator_scale
    variable timeline_on
    variable display_height
    variable display_width
    variable display_front
          
    molinfo $statusIndicator_mol set center_matrix [list [transidentity]]
    molinfo $statusIndicator_mol set rotate_matrix [list [transidentity]]
    molinfo $statusIndicator_mol set global_matrix [list [transidentity]]
    molinfo $statusIndicator_mol set scale_matrix  [molinfo top get scale_matrix]
    
    set statusIndicator_scale [lindex [molinfo $statusIndicator_mol get scale_matrix] 0 0 0]
    set display_height [expr 0.25*[display get height]/$statusIndicator_scale]
    set display_width [expr $display_height*[lindex [display get size] 0]/[lindex [display get size] 1]]
    
    if [string equal [display get projection] "Orthographic"] {
        set display_front [expr (2.-[display get nearclip]-0.001)/$statusIndicator_scale]
    } else {
        set display_front 0.
    }
     
    graphics $statusIndicator_mol delete all
    
    if $timeline_on {draw}
    
}

proc ::statusIndicator::draw {} {

    variable header
    variable timestep
    variable error_msg
    variable statusIndicator_mol
    variable display_height
    variable display_width
    variable display_front
    variable timeLabel
    variable percentage
    variable unit

    if { $timestep <= 0.0 } { 
        set error_msg "Error: timestep must be >= 0"
        debug $error_msg 
        return
    }
    if { [molinfo top get numframes] == 0 } { 
        set error_msg "Error: top molecule has no frames"
        debug $error_msg 
        return
    } 
    set error_msg "" 

    global vmd_frame
    global st
    global tf
    #graphics 0 delete $st
    #graphics 0 color blue

    # Scaling factor:
    #lindex [molinfo top get scale_matrix] 0 0 0

    set percentage [expr {double($vmd_frame([molinfo top]))/([molinfo top get numframes]-1)}]
    set time [format "%2.1f" [expr $vmd_frame([molinfo top]) * $timestep]]
    set tf [format "%2.1f" [expr ([molinfo top get numframes] -1) * $timestep ]]
    set disp "$display_width $display_height $display_front"
    set pixelwidth [expr 2.*$display_width/[lindex [display get size] 0]]
    set pixelheight [expr 2.*$display_height/[lindex [display get size] 1]]
    
    # progress bar thickness
    set thickness [expr {0.02*2.*$display_height}] ;# 3% of display height

    set margin [expr {0.01*2*$display_height}]  
    set bottom [expr {-$display_height + $margin}]
    set top [expr {$bottom + $thickness}]
    set left [expr {-0.95*$display_width}]
    set right [expr {0.95*$display_width}]
    
    set top_inner [expr {$top - 1*$pixelheight}]
    set left_inner [expr {$left + 1*$pixelheight}]
    set right_inner [expr {$right - 1*$pixelheight}]
    set bottom_inner [expr {$bottom + 1*$pixelheight}]

    # Draw white background
    #graphics $statusIndicator_mol materials off
    #graphics $statusIndicator_mol color white
    #::statusIndicator::draw_rectangle [expr {-$display_width}] [expr {-0.8*$display_height}] $display_width [expr {-$display_height}] $display_front

    # Draw gray outer rectangle
    graphics $statusIndicator_mol materials off
    graphics $statusIndicator_mol color gray
    # draw 2 px behind for renderers to get it right
    ::statusIndicator::draw_rectangle $left $top $right $bottom [expr {$display_front-2*$pixelwidth}]

    # Draw white inner rectangle
    graphics $statusIndicator_mol materials off
    graphics $statusIndicator_mol color white
    # draw 1 px behind for renderers to get it right
    ::statusIndicator::draw_rectangle $left_inner $top_inner $right_inner $bottom_inner [expr {$display_front-1*$pixelwidth}]

    # Draw rectangle scaled to $percentage (progress bar) filling inner rectangle when $percentage = 1
    graphics $statusIndicator_mol materials off
    graphics $statusIndicator_mol color silver
    ::statusIndicator::draw_rectangle $left_inner $top_inner [expr {$left_inner + $percentage*($right_inner-$left_inner)}] $bottom_inner $display_front
    
    graphics $statusIndicator_mol color $::statusIndicator::statusIndicator_color
    #graphics $statusIndicator_mol color black
    set timeLabel [format "Time: %.02f / %.02f %s" $time $tf $unit]
    graphics $statusIndicator_mol text "$left_inner [expr {-0.87*$display_height}] $display_front" $timeLabel size 2.0 thickness 2.0

    set top [expr {$display_height - $margin - 10*$pixelheight}]
    graphics $statusIndicator_mol text "$left_inner $top $display_front" $header size 1.0

}
  
proc ::statusIndicator::draw_rectangle { left top right bottom z } {
    variable statusIndicator_mol
    graphics $statusIndicator_mol triangle "$left $top $z" "$right $top $z" "$left $bottom $z"
    graphics $statusIndicator_mol triangle "$left $bottom $z" "$right $top $z" "$right $bottom $z"
}

proc ::statusIndicator::frame_changed { args } {
    if {"[lindex $args 0]" == "vmd_logfile"} {
        #puts [format "Log entry: %s" $::vmd_logfile]
        if {"$::vmd_logfile" == "exit"} {
            debug "VMD is exiting"
            return
        }
    }
    redraw
}

proc ::statusIndicator::timestep_changed { args } {
  redraw
}

proc ::statusIndicator::toggled {} {
    variable timeline_on
    if {$timeline_on} {
        enable
        redraw
    }
    if {!$timeline_on} {
        disable 1
    } 
}

proc statusIndicator_tk {} {
    return [statusIndicator::gui]
}

proc ::statusIndicator::timestepValidate { newval } {
    variable timestep
    if { ![string length $newval] } { return 1 }     ;# allow emptying the field
    if { ![string is double $newval] } { return 0 }  ;# but otherwise, allow no other input than doubles
    return 1
}

proc ::statusIndicator::stateChanged {} {
    variable timeline_on
    variable timeline_checked
    if { !$timeline_on && $timeline_checked } {
        set timeline_on 1
        ::statusIndicator::toggled
    } elseif { $timeline_on && !$timeline_checked } {
        set timeline_on 0
        ::statusIndicator::toggled
    }
}  

proc statusIndicator::gui {} {
    variable w
    variable statusIndicator_state
    variable timestep

    # If already initialized, just turn on
    if [winfo exists .progressindicator] {
        wm deiconify .progressindicator
        raise .progressindicator
        return $w
    }

    # Initialize window
    set w [::toplevel .progressindicator]
    # since there are no ttk::toplevel method (why not?) See http://wiki.tcl.tk/11075
    place [ttk::frame $w.bg -padding 10] -x 0 -y 0 -relwidth 1 -relheight 1
    #pack [ttk::frame $w.bg -padding 10] -side top -fill both

    #grid columnconfigure $w.bg 0 -weight 1
    grid columnconfigure $w.bg 1 -weight 1
    #grid columnconfigure $w.bg 2 -weight 1
    #pack $w.uc -side top -fill x -padx 10 -pady 4

    wm title $w "statusIndicator Settings"
    wm resizable $w 1 1
    wm minsize  $w 200 100  
    
    ## Checkbox:
    ttk::checkbutton $w.bg.timeline -text "Draw timeline" \
        -variable ::statusIndicator::timeline_checked \
        -command ::statusIndicator::stateChanged
    grid $w.bg.timeline -row 0 -column 0 -columnspan 3 -sticky w

    ## Timestep entry:
    ttk::label $w.bg.timestep_label -text "Timestep:"
    ttk::entry $w.bg.timestep -width 10 \
        -textvariable ::statusIndicator::timestep \
        -validate key -validatecommand {::statusIndicator::timestepValidate %P}
    ttk::optionmenu $w.bg.unit ::statusIndicator::unit "fs" "ps" "ns"
    grid $w.bg.timestep_label -row 1 -column 0 -sticky w
    grid $w.bg.timestep -row 1 -column 1 -sticky we
    grid $w.bg.unit -row 1 -column 2 -sticky w

    ## Header entry:
    ttk::label $w.bg.header_label -text "Header:"
    ttk::entry $w.bg.header -width 40 \
      -textvariable ::statusIndicator::header
    grid $w.bg.header_label -row 2 -column 0 -sticky w
    grid $w.bg.header -row 2 -column 1 -columnspan 2 -sticky we

    ## Unit entry:
    #ttk::label $w.bg.unit_label -text "Unit:"
    #grid $w.bg.unit_label -row 3 -column 0 -sticky w
    #grid $w.bg.unit -row 3 -column 1 -sticky we
    
    ## Error emssage:
    ttk::label $w.bg.errormsg -foreground "red" -textvariable ::statusIndicator::error_msg
    grid $w.bg.errormsg -row 3 -column 0 -columnspan 3 -sticky w
    
    return $w
}
