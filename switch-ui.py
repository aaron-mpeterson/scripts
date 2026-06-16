#!/usr/bin/env python3

# A fun project I work on when work is slow!
# Ideas:
#   Add tabs (summary, one for each switch showing more info)
#   Add command line functionality to pass commands to switches (all or individual)

import curses
import subprocess
import threading
import time 
import re

data_lock = threading.Lock()
keep_running = True 

# #Hardcoded list of switch locations if needed
# switch_locations = ('x9000c1r0b0', 'x9000c1r1b0', 'x9000c1r2b0','x9000c1r3b0',
#                     'x9000c1r4b0','x9000c1r5b0','x9000c1r6b0', 'x9000c1r7b0',
#                     'x9000c3r0b0', 'x9000c3r1b0', 'x9000c3r2b0', 'x9000c3r3b0')

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


# default values to display
version_data = {
    sw: {
        'Firmware version': 'Loading...',
        'Uboot version': 'Loading...',
        'Recovery image': 'Loading...',
        'Status': 'Loading...'
    }
    for sw in switch_locations
}


def clean_up_string(string):
    clean_string = string.replace("OK Enabled", "").replace("OK Updating", "").strip()

    match = re.compile(r"^([a-zA-Z0-9\.]+-[0-9]+)").match(clean_string)
    if match:
        return match.group(1)
    # if can't match using regex pattern, return the full string 
    return clean_string


def parse_cfirmware_output():
    # Default values
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
        cmd = ["cfirmware", "sc", "checkall", "x9000c*"]
        result = subprocess.run(cmd, universal_newlines=True,
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE,
                                timeout=15)

        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue

            if ":" in line:
                location = line.split(":")[0].strip()
                if location in parsed_data:
                    current_switch = location
                    parsed_data[current_switch]['Status'] = 'Online'

            if current_switch:
                if "BMC" in line:
                    if "Absent" in line:
                    parsed_data[current_switch]['Firmware version'] = 'Absent'
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
        pass

    return parsed_data



def multi_command_worker():
    global version_data, keep_running

    while keep_running:
        cfirmware_data = parse_cfirmware_output()

        with data_lock:
            for sw in switch_locations:
                version_data[sw] = cfirmware_data[sw]

        # sleep for 5 seconds before checking again
        for _ in range(50):
            if not keep_running:
                break
            time.sleep(0.1)



###########################################
##           MAIN CURSES LOOP            ##
###########################################

def main(stdscr):
    global keep_running

    # disable the cursor and set refresh rate  
    curses.curs_set(0)
    stdscr.timeout(100)

    # start the thread to run commands
    # This helps prevent flickering and weird issues with timing 
    worker_thread = threading.Thread(target=multi_command_worker)
    worker_thread.start()

    # curses color pairs
    curses.init_pair(1, curses.COLOR_GREEN, curses.COLOR_BLACK)

    # initialize some useful things 
    height, width = stdscr.getmaxyx()
    current_tab = 0

    # Create sw_boxes outside the loop to prevent flickering
    box_height = 6
    box_width = 38
    start_y, start_x = 4, 2
    y_gap, x_gap = 1, 2

    sw_boxes = {}
    for index, sw in enumerate(switch_locations):
        # math to create a grid of boxes (no more than 4 rows)
        row_idx = index % 4
        col_idx = index // 4
        
        # center the columns (this is nauseating math but it works)
        total_cols = (len(switch_locations) + 3) // 4
        total_grid_width = (total_cols * (box_width)) + ((total_cols - 1) * x_gap)

        win_y = start_y + (row_idx * (box_height + y_gap))
        left_edge = (width - total_grid_width) // 2
        win_x = left_edge + (col_idx * (box_width + x_gap))

        sw_boxes[sw] = curses.newwin(box_height, box_width, win_y, win_x)


    # Create tab windows outside of loop
    tab_win_height = height - 8
    tab_win_width = width - 8
    tab_start_y = 2 
    tab_start_x = 4 
    
    tab_window = curses.newwin(tab_win_height, tab_win_width, tab_start_y, tab_start_x)

    
    while True:
        stdscr.erase()  # changed to .erase() because .clear() was giving me seizures

        # Copy the latest data to use inside the loop without causing slowdown
        with data_lock:
            latest_version_data = version_data.copy()
        
        height, width = stdscr.getmaxyx()

        title = "=== SWITCH DASHBOARD ==="
        stdscr.addstr(0, max(2, (width - len(title)) // 2), title, curses.A_BOLD)

        keybind_bar = "Press 'q' to quit   |   Use arrow keys to switch tabs"
        stdscr.addstr(height - 2, 2, keybind_bar)
        stdscr.chgat(height -2, 0, -1, curses.A_REVERSE)

        
        # add tabs at the top
        max_tabs = len(switch_locations)  # this math works because of the 'SUMMARY' tab, remember to adjust if changing that
        tabs = ["SUMMARY"]

        for location in switch_locations[:12]:
            tabs.append(location)

        tabs_offset = 2 

        for tab_num, tab_name in enumerate(tabs):
            if tab_num == current_tab:
                stdscr.attron(curses.A_REVERSE)
            if tab_num != current_tab:
                stdscr.attron(curses.A_DIM)

            stdscr.addstr(1, tabs_offset, f" {tab_name} ")
            stdscr.attroff(curses.A_REVERSE)
            stdscr.attroff(curses.A_DIM)

            # for debugging 
            stdscr.addstr(height - 3, 1, f"Current tab is: {current_tab}, Max tab is {max_tabs}")

            # space the tabs
            tabs_offset += len(tab_name) + 2

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

        
        # tabs for each switch location
        if current_tab >> 0:
            tab_window.erase()
            tab_window.box()
            tab_window.addstr(2, 2, "This is a tab window")
            tab_window.addstr(3, 2, f"This tab belongs to {tabs[current_tab]}")
            tab_window.noutrefresh()


        # refresh the whole screen 
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
        if key == ord('u'):
            break
        if key == ord('q'):
            break

        # refresh the whole screen 
        curses.doupdate()

    keep_running = False
    worker_thread.join()

curses.wrapper(main)
