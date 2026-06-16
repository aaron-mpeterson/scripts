#!/usr/bin/python3



## Get switch locations 
def get_switch_locations():
    try:
        cmd = ["cnodes", "--platform-controller"]
        result = subprocess.run(cmd, universal_newlines=True,
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE)

        switches = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if switches:
            return tuple(switches)
    except subprocess.CalledProcessError:
        pass
switch_locations = get_switch_locations()



## Check if each switch is secure booted
def check_secure_boot():
    try:
        cmd = ["clush", "-B", "-w", "$(cnodes --platform-controller)", "cat", "/proc/cmdline"]
        result = subprocess.run(cmd, universal_newlines=True,
                                stdout=subprocess.PIPE, 
                                stderr=subprocess.PIPE)

        for line in result.stdout:
            if not line:
                continue

            if "sec_boot=1" in line:



## Display which switches have SB



## Bring the non-SB switches up to latest non-SB uboot version (ignore switches with SB)
