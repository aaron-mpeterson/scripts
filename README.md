# scripts
A small collection of scripts I wrote and use daily for debugging switches. These are not particularly complex or large scripts. 
Their main purpose is to simplify the flashing/testing process so debug techs who haven't been trained on testing switches (or aren't as familiar with the command line) can easily step in if needed.

Brief description of each:
1. cmcinventory.sh - automates the process of discovering switches in the test rack while displaying messages to keep techs in the loop with what's happening.
2. colorado_loopback_results.sh - short script to display the results of loopback testing in one place. No more jumping between directories. Passes/fails are color coded for ease of use.
3. dgrloopbackWC - just an edited version of 'dgrloopback' (written for Colorados) to work with Wildcats. Tweaked the args code and the command used in subprocess.run() to match Wildcat usage
4. port_temps.sh - one line script to display temps for front ports of all switches installed in rack. Rarely used.
5. sbcheck.sh - simple script to check if switches have secure boot enabled and handle updating the uboot and pC image only if they don't. Saves user from many headaches.
6. switch-ui.py - TUI displaying info about switches installed in the rack using Python's curses library. Does not affect state. Currently displays software version info, voltages/temps, and board info (SN, PN, etc.)
