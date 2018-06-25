proc finalConfig {} {

################################################################################
set testNo finalConfig
set title "Getting Configurations from DUTs after test script execution"
###############################################################################

#Declaring global variables
global DUT1_CONNECT
global DUT2_CONNECT
global DUT3_CONNECT
global DUT4_CONNECT
global DUT5_CONNECT

set fd_res [open_result_file "$testNo"]
set time1 [clock seconds]
result_h1 "$title"
report_start_test "$title"

set fd_in [open "finalConfig.txt" "w"]

set fd1 [open "DUT1.txt" "w"]
Login $DUT1_CONNECT
SendACmd "show configuration" NULL $fd1
close $fd1

set fd1 [open "DUT1.txt" "r"]
set lines [split [read $fd1] "\n"]
set lines [lreplace $lines end end]
puts -nonewline $fd_in [join $lines \n]
close $fd1

set fd1 [open "DUT1.txt" "w"]
SendACmd "ls" NULL $fd1
close $fd1

set fd1 [open "DUT1.txt" "r"]
set lines [split [read $fd1] "\n"]
set lines [lreplace $lines end end]
puts -nonewline $fd_in [join $lines \n]
close $fd1

Login $DUT2_CONNECT
set fd2 [open "DUT2.txt" "w"]
SendACmd "show configuration" NULL $fd2
close $fd2

set fd2 [open "DUT2.txt" "r"]
set lines [split [read $fd2] "\n"]
set lines [lreplace $lines end end]
close $fd2
puts -nonewline $fd_in [join $lines \n]

Login $DUT2_CONNECT
set fd2 [open "DUT2.txt" "w"]
SendACmd "ls" NULL $fd2
close $fd2

set fd2 [open "DUT2.txt" "r"]
set lines [split [read $fd2] "\n"]
set lines [lreplace $lines end end]
close $fd2
puts -nonewline $fd_in [join $lines \n]

if [info exists DUT3_CONNECT] {
        Login $DUT3_CONNECT
        set fd3 [open "DUT3.txt" "w"]
        SendACmd "show configuration" NULL $fd3
        close $fd3

        set fd3 [open "DUT3.txt" "r"]
        set lines [split [read $fd3] "\n"]
        set lines [lreplace $lines end end]
        close $fd3

        puts -nonewline $fd_in [join $lines \n]

        set fd3 [open "DUT3.txt" "w"]
        SendACmd "ls" NULL $fd3
        close $fd3

        set fd3 [open "DUT3.txt" "r"]
        set lines [split [read $fd3] "\n"]
        set lines [lreplace $lines end end]
        close $fd3

        puts -nonewline $fd_in [join $lines \n]
        file delete "DUT3.txt"
}

if [info exists DUT4_CONNECT] {
        Login $DUT4_CONNECT
        set fd4 [open "DUT4.txt" "w"]
        SendACmd "show configuration" NULL $fd4
        close $fd4

        set fd4 [open "DUT4.txt" "r"]
        set lines [split [read $fd4] "\n"]
        set lines [lreplace $lines end end]
        close $fd4

        puts -nonewline $fd_in [join $lines \n]

        set fd4 [open "DUT4.txt" "w"]
        SendACmd "ls" NULL $fd4
        close $fd4

        set fd4 [open "DUT4.txt" "r"]
        set lines [split [read $fd4] "\n"]
        set lines [lreplace $lines end end]
        close $fd4

        puts -nonewline $fd_in [join $lines \n]
        file delete "DUT4.txt"
}

if [info exists DUT5_CONNECT] {
        Login $DUT5_CONNECT
        set fd5 [open "DUT5.txt" "w"]
        SendACmd "show configuration" NULL $fd5
        close $fd5

        set fd5 [open "DUT5.txt" "r"]
        set lines [split [read $fd5] "\n"]
        set lines [lreplace $lines end end]
        close $fd5

        puts -nonewline $fd_in [join $lines \n]
        set fd5 [open "DUT5.txt" "w"]
        SendACmd "ls" NULL $fd5
        close $fd5

        set fd5 [open "DUT5.txt" "r"]
        set lines [split [read $fd5] "\n"]
        set lines [lreplace $lines end end]
        close $fd5

        puts -nonewline $fd_in [join $lines \n]
        file delete "DUT5.txt"
}
close $fd_in

file delete "DUT1.txt"
file delete "DUT2.txt"

set time2 [clock seconds]
result_p "*** Time for $testNo = [expr $time2-$time1] secs\n\n"
close_result_file
report_end_test
}
