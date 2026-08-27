#!/usr/bin/env bash



#DATA PARSING 
#---------------------------------------------------------------------
parse_nics() {
    #N0 
    #----------------------------------------------------------------- 
    if grep -A6 "High-speed NIC" /var/log/n0/current | grep -A6 "NIC0" | grep -q "(Actual):  x16"; then
        n0_NIC0=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_NIC0=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -A6 "High-speed NIC" /var/log/n0/current | grep -A6 "NIC1" | grep -q "(Actual):  x16"; then
        n0_NIC1=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_NIC1=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -A6 "High-speed NIC" /var/log/n0/current | grep -A6 "NIC2" | grep -q "(Actual):  x16"; then
        n0_NIC2=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_NIC2=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -A6 "High-speed NIC" /var/log/n0/current | grep -A6 "NIC3" | grep -q "(Actual):  x16"; then
        n0_NIC3=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_NIC3=$'\e[31m'"Fail"$'\e[0m'
    fi
    #----------------------------------------------------------------- 

    #N1 
    #----------------------------------------------------------------- 
    if grep -A7 "High-speed NIC" /var/log/n1/current | grep -A6 "NIC0" | grep -q "(Actual):  x16"; then
        n1_NIC0=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_NIC0=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -A7 "High-speed NIC" /var/log/n1/current | grep -A6 "NIC1" | grep -q "(Actual):  x16"; then
        n1_NIC1=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_NIC1=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -A7 "High-speed NIC" /var/log/n1/current | grep -A6 "NIC2" | grep -q "(Actual):  x16"; then
        n1_NIC2=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_NIC2=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -A7 "High-speed NIC" /var/log/n1/current | grep -A6 "NIC3" | grep -q "(Actual):  x16"; then
        n1_NIC3=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_NIC3=$'\e[31m'"Fail"$'\e[0m'
    fi
    #----------------------------------------------------------------- 
}

parse_cpus() {
    if grep -q -A12 "CPU0" /var/log/n0/current; then
        n0_CPU0=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_CPU0=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -q -A12 "CPU1" /var/log/n0/current; then
        n0_CPU1=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_CPU1=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -q -A12 "CPU0" /var/log/n1/current; then
        n1_CPU0=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_CPU0=$'\e[31m'"Fail"$'\e[0m'
    fi

    if grep -q -A12 "CPU1" /var/log/n1/current; then
        n1_CPU1=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_CPU1=$'\e[31m'"Fail"$'\e[0m'
    fi
}

parse_smns() {
    if grep -A6 "F0 - System Management NIC" /var/log/n0/current | grep -q "Link Width (Actual):  x1"; then
        n0_SMNs=$'\e[32m'"Pass"$'\e[0m'
    else
        n0_SMNs=$'\e[31m'"Fail"$'\e[0m'
    fi 

    if grep -A6 "F0 - System Management NIC" /var/log/n1/current | grep -q "Link Width (Actual):  x1"; then
        n1_SMNs=$'\e[32m'"Pass"$'\e[0m'
    else
        n1_SMNs=$'\e[31m'"Fail"$'\e[0m'
    fi 
}


#---------------------------------------------------------------------



#VARIABLE SETUP 
#---------------------------------------------------------------------
update_variables() {
    #current file sizes 
    n0_current=$(stat -c%s /var/log/n0/current)
    n1_current=$(stat -c%s /var/log/n1/current)

    #bios versions
    n0_bios=$(cat /var/log/n0/current | grep HPE_VERSION | awk '{print $3}')
    n1_bios=$(cat /var/log/n1/current | grep HPE_VERSION | awk '{print $3}')

    #DIMMs
    n0_DIMMs=$(cat /var/log/n0/current | grep "CapacityMiB: 16384" | wc -l)
    n1_DIMMs=$(cat /var/log/n1/current | grep "CapacityMiB: 16384" | wc -l)

    #NICs
    parse_nics

    #CPUs 
    parse_cpus

    #SMNs 
    parse_smns
}
#---------------------------------------------------------------------



#DISPLAY FUNCTIONS
#---------------------------------------------------------------------
display_summary() {
    # tput cup 0 0
    clear
    echo "Time elapsed:  $SECONDS"
    echo

    ##alternate idea for text display
    #--------------------------------- 
    printf "%-37s %-37s\n" "N0" "N1"
    printf "%-37s %-37s\n" "Current file size: $n0_current" "Current file size: $n1_current"
    printf "%-37s %-37s\n\n" "Bios Version: $n0_bios" "Bios Version: $n1_bios"
    printf "%-16s %-20s %-16s %-20s\n" "DIMMs:" "$n0_DIMMs" "DIMMs" "$n1_DIMMs"
    printf "%-16s %-29s %-16s %-20s\n" "NIC0:" "$n0_NIC0" "NIC0:" "$n1_NIC0"
    printf "%-16s %-29s %-16s %-20s\n" "NIC1:" "$n0_NIC1" "NIC1:" "$n1_NIC1"
    printf "%-16s %-29s %-16s %-20s\n" "NIC2:" "$n0_NIC2" "NIC2:" "$n1_NIC2"
    printf "%-16s %-29s %-16s %-20s\n" "NIC3:" "$n0_NIC3" "NIC3:" "$n1_NIC3"
    printf "%-16s %-29s %-16s %-20s\n" "CPU0:" "$n0_CPU0" "CPU0:" "$n1_CPU0"
    printf "%-16s %-29s %-16s %-20s\n" "CPU1:" "$n0_CPU1" "CPU1:" "$n1_CPU1"
    printf "%-16s %-29s %-16s %-20s\n" "SMNs:" "$n0_SMNs" "SMNs:" "$n1_SMNs"

    printf "\n\n\n"
    printf "(D) DIMM info  |  (N) NIC info\n"
    printf "(C) CPU info   |  (S) SysMgmt NIC info\n"
    printf "(Q) Quit\n"
    #---------------------------------- 
}

display_dimms() {
    clear 
    echo "DIMM INFO: Press any key to return to summary"
    echo "--------------------------------------------------------------"
    echo
    echo "Node 0 DIMMs:"
    grep "CapacityMiB: 16384" /var/log/n0/current | awk '{$1=""; print}'
    echo 
    echo "Node 1 DIMMs:"
    grep "CapacityMiB: 16384" /var/log/n1/current | awk '{$1=""; print}'
    read -rn1 
}

display_cpus() {
    clear 
    echo "CPU INFO: Press any key to return to summary"
    echo "--------------------------------------------------------------"
    echo
    echo "Node 0 CPUs:"
    cat /var/log/n0/current | grep -A12 "CPU0:" | awk '{$1=""; print}'
    cat /var/log/n0/current | grep -A12 "CPU1:" | awk '{$1=""; print}'
    echo
    echo "Node 1 CPUs:"
    cat /var/log/n1/current | grep -A12 "CPU0:" | awk '{$1=""; print}'
    cat /var/log/n1/current | grep -A12 "CPU1:" | awk '{$1=""; print}'
    read -rn1
}

display_nics() {
    clear 
    echo "NIC INFO: Press any key to return to summary"
    echo "--------------------------------------------------------------"
    echo
    echo "Node 0 NICs:"
    cat /var/log/n0/current | grep -A6 "High-speed NIC" | awk '{$1=""; print}'
    echo
    echo "Node 1 NICs:"
    cat /var/log/n1/current | grep -A6 "High-speed NIC" | awk '{$1=""; print}'
    read -rn1
}

display_smn() {
    clear 
    echo "SYSTEM MANAGEMENT NIC INFO: Press any key to return to summary"
    echo "--------------------------------------------------------------"
    echo
    echo "Node 0 System Management NIC:"
    cat /var/log/n0/current | grep -A 6 "F0 - System Management NIC" | awk '{$1=""; print}'
    echo
    echo "Node 1 System Management NIC:"
    cat /var/log/n1/current | grep -A 6 "F0 - System Management NIC" | awk '{$1=""; print}'
    read -rn1
}
#---------------------------------------------------------------------



#USER INPUT 
#---------------------------------------------------------------------
get_user_input() {
    read -t 3 -rsn1 key
    case $key in 
        [qQ])
            printf "Exiting...\n"
            exit 0;;
        [dD])
            display_dimms;;
        [cC])
            display_cpus;;
        [nN])
            display_nics;;
        [sS])
            display_smn;;
        *)  ;;

    esac
}
#---------------------------------------------------------------------



#MAIN LOOP
#---------------------------------------------------------------------
while true; do
    update_variables
    display_summary
    get_user_input
done
#---------------------------------------------------------------------
