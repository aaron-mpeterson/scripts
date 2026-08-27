#!/usr/bin/env python3

import curses
import subprocess
import threading
import time 
import re
import sys

keep_running = True
data_lock = threading.Lock()

################################
###---GET SWITCH LOCATIONS---###
################################
def get_switch_locations():
    try:
        cmd = ["cnodes", "--switch-controller"]
        result = subprocess.run(cmd, universal_newlines=True,
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE)

        switches = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if switches:
            return tuple(switches)
    except subprocess.CalledProcessError:
        pass
switch_locations = get_switch_locations()

switch_locations_hardcoded = ('x9000c1r0b0', 'x9000c1r1b0', 'x9000c1r2b0','x9000c1r3b0',
                              'x9000c1r4b0','x9000c1r5b0','x9000c1r6b0', 'x9000c1r7b0',
                              'x9000c3r0b0', 'x9000c3r1b0', 'x9000c3r2b0', 'x9000c3r3b0')
if not switch_locations:
    switch_locations = switch_locations_hardcoded




###############################
###---INITIALIZE MESSAGES---###
###############################
debug_log_output = 'Waiting for output from command...'
dgrpower_data = "Waiting for data..."
eeprom_data = "Waiting for data..."
version_data = {
    sw: {
        'Firmware version': 'Loading...',
        'Uboot version': 'Loading...',
        'Recovery image': 'Loading...',
        'Status': 'Loading...'
    }
    for sw in switch_locations
}




#############################
###---COMMAND FUNCTIONS---###
#############################
def clean_up_string(string):
    clean_string = string.replace("OK Enabled", "").strip()

    match = re.compile(r"^([a-zA-Z0-9\.]+-[0-9]+)").match(clean_string)
    if match:
        return match.group(1)
    # if can't match using regex pattern, return the full string 
    return clean_string


def command_runner(cmd):
    result = subprocess.run(cmd, shell=True,
                            executable="/bin/bash",
                            universal_newlines=True,
                            stdout=subprocess.PIPE, 
                            stderr=subprocess.PIPE,
                            timeout=8)
    return result.stdout
    


def get_cfirmware_output():
    global debug_log_output

    #fallback data 
    parsed_data = {
        sw: {
            'Firmware version': 'Unknown',
            'Uboot version': 'Unknown',
            'Recovery image': 'Unknown',
            'Status': 'Offline'
        } for sw in switch_locations
    }
    try:
        current_switch = None
        cmd = 'cfirmware sc checkall x9000c*'
        result = command_runner(cmd)
        #debug_log_output = result.stdout

        for line in result.splitlines():
            line = line.strip()
            if not line:
                continue

            if ":" in line:
                location = line.split(":")[0].strip()
                if location in parsed_data:
                    current_switch = location
                    if "ClientConnectorError" in line:
                        parsed_data[current_switch]['Status'] = 'Offline'
                        continue
                    parsed_data[current_switch]['Status'] = 'Online'

            if current_switch:
                if "BMC" in line:
                    if "Absent" in line:
                        parsed_data[current_switch]['Firmware version'] = 'Absent'
                        continue
                    if "Updating" in line:
                        parsed_data[current_switch]['Firmware version'] = 'Updating'
                        continue
                    version_number = line.split()[-1]
                    cleaned = clean_up_string(version_number)
                    parsed_data[current_switch]['Firmware version'] = cleaned if cleaned else version_number

                elif "Bootloader" in line:
                    if "secure" in line:
                        parsed_data[current_switch]['Uboot version'] = 'Secure Booted'
                    else:
                        version_number = line.split()[-1]
                        cleaned = clean_up_string(version_number)
                        parsed_data[current_switch]['Uboot version'] = cleaned if cleaned else version_number
                
                elif "Recovery" in line:
                    version_number = line.split()[-1].strip()
                    cleaned = clean_up_string(version_number)
                    parsed_data[current_switch]['Recovery image'] = cleaned if cleaned else version_number
    
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return "ERROR"

    return parsed_data


def get_dgrpower_output():
    global debug_log_output
    try:
        cmd = 'clush -w $(cnodes --switch-controller|nodeset -f) dgrpower'
        result = command_runner(cmd)
        #debug_log_output = result.stdout

    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return "ERROR"
    return result


def get_eeprom_output():
    global debug_log_output
    try:
        cmd = 'clush -w $(cnodes --platform-controller|nodeset -f) "hexdump -C /sys/class/i2c-adapter/i2c-6/6-0056/eeprom"; clush -w $(cnodes --switch-controller|nodeset -f) "hexdump -C /sys/class/i2c-adapter/i2c-0/0-0056/eeprom" ' 
        result = command_runner(cmd)
        #debug_log_output = result.stderr
    
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return "ERROR"
    return result


def command_worker():
    global version_data, dgrpower_data, eeprom_data, keep_running
    
    while keep_running:
        cfirmware_data = get_cfirmware_output()
        dgrpower_data = get_dgrpower_output()
        eeprom_data = get_eeprom_output()

        for sw in switch_locations:
            version_data[sw] = cfirmware_data[sw]
        
        for _ in range(20):
            if not keep_running:
                break 
            time.sleep(0.1)



################
###---MAIN---###
################

def main(stdscr):
    global keep_running

    worker_thread = threading.Thread(target=command_worker)
    worker_thread.start()

    #curses options
    curses.curs_set(0)
    stdscr.timeout(100)
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)

    # initialize some useful things 
    height, width = stdscr.getmaxyx()

    # debug window 
    debug_win = curses.newwin(height -4, 120, 2, 2)


    # #Create boxes for each switch
    sw_boxes = {}
    box_height = 6
    box_width = 38
    start_y, start_x = 4, 2
    y_gap, x_gap = 1, 2

    for index, sw in enumerate(switch_locations):
        row_idx = index % 4
        col_idx = index // 4
        total_cols = (len(switch_locations) + 3) // 4

        total_grid_width = (total_cols * (box_width)) + ((total_cols - 1) * x_gap)
        left_edge = (width - total_grid_width) // 2
        win_y = start_y + (row_idx * (box_height + y_gap))
        win_x = left_edge + (col_idx * (box_width + x_gap))

        sw_boxes[sw] = curses.newwin(box_height, box_width, win_y, win_x)


    #Create tabs for each switch 
    sw_tabs = {}

    tab_win_height = height - 8
    tab_win_width = width - 8
    tab_start_y = 2 
    tab_start_x = 4 

    current_tab = 0
    for index, sw in enumerate(switch_locations):
        sw_tabs[sw] = curses.newwin(tab_win_height, tab_win_width, tab_start_y, tab_start_x)

    


    while keep_running:
        stdscr.erase()

        # Copy the latest data
        with data_lock:
            latest_version_data = version_data.copy()
            latest_power_data = dgrpower_data
            latest_eeprom_data = eeprom_data
            latest_debug_log = debug_log_output


        title = "=== SWITCH DASHBOARD ==="
        stdscr.addstr(0, max(2, (width - len(title)) // 2), title, curses.A_BOLD)

        keybind_bar = "Press 'q' to quit   |   Use arrow keys to switch tabs"
        stdscr.addstr(height - 2, 2, keybind_bar)
        stdscr.chgat(height -2, 0, -1, curses.A_REVERSE)

        max_tabs = len(switch_locations)  # this math works because of the 'SUMMARY' tab, remember to adjust if changing that
        tab_list = ["SUMMARY"]
        tabs_offset = 2 


        # stops the screen from updating until told to with .doupdate(), prevents flickering
        stdscr.noutrefresh()
        


        for sw, win in sw_boxes.items():
            displayed_data = latest_version_data[sw]

            win.erase()
            win.box()

            win.addstr(0, 2, f" {sw} ", curses.A_BOLD)
            win.addstr(1, 2, f"FW Ver:   {displayed_data['Firmware version']}")
            win.addstr(2, 2, f"Uboot:    {displayed_data['Uboot version']}")
            win.addstr(3, 2, f"Recovery: {displayed_data['Recovery image']}")

            win.addstr(4, 2, "Status:   ")
            status_color = curses.color_pair(1) if displayed_data['Status'] == 'Online' else curses.A_DIM
            win.addstr(4, 12, displayed_data['Status'], status_color | curses.A_BOLD)

            win.noutrefresh()



        for location in switch_locations[:12]:
            tab_list.append(location)


        for sw, tab_window in sw_tabs.items():
            pc = sw.replace("b","m")

            if current_tab >> 0 and sw == tab_list[current_tab]:
                tab_window.erase()
                tab_window.box()

                tab_window.addstr(2, 3, f"Waiting for data to load...")
                dgrpower_y = 2
                
                for i, line in enumerate(latest_power_data.split("\n")):
                    if sw in line:
                        data = line.split(":",1)[1]
                        tab_window.addstr(dgrpower_y, 2, data[:66])
                        dgrpower_y += 1
                
                eeprom_y = 2
                for i, line in enumerate(latest_eeprom_data.split("\n")):
                    if pc in line:
                        data = line.split(":",1)[1]
                        tab_window.addstr(eeprom_y,  78, data[61:])
                        eeprom_y += 1
                    if sw in line:
                        data = line.split(":",1)[1]
                        tab_window.addstr(eeprom_y,  78, data[61:])
                        eeprom_y += 1
                tab_window.noutrefresh()


        for tab_num, tab_name in enumerate(tab_list):
            if tab_num == current_tab:
                stdscr.attron(curses.A_REVERSE)
            if tab_num != current_tab:
                stdscr.attron(curses.A_DIM)

            stdscr.addstr(1, tabs_offset, f" {tab_name} ")
            stdscr.attroff(curses.A_REVERSE)
            stdscr.attroff(curses.A_DIM)
            tabs_offset += len(tab_name) + 2
            


        # debug_win.erase()
        # debug_win.box()
        # debug_win.addstr(1, 2, "DEBUG OUTPUT LOG:", curses.A_UNDERLINE)
        #
        # for i, line in enumerate(latest_debug_log.split("\n")):
        #
        #     debug_win.addstr(2 + i, 2, line)
        # debug_win.noutrefresh()


        # refresh the whole screen 
        # time.sleep(0.03)
        curses.doupdate()

        key = stdscr.getch()
        if key == curses.KEY_RIGHT:
            current_tab += 1
            if current_tab == max_tabs + 1:
                current_tab = 0 
        if key == curses.KEY_LEFT:
            current_tab += -1
            if current_tab == -1:
                current_tab = max_tabs
        if key == ord('q'):
            keep_running = False
            worker_thread.join()
            sys.exit(0)

        # refresh the whole screen 
        # curses.doupdate()

    keep_running = False
    worker_thread.join()

curses.wrapper(main)
