#!/bin/bash

#Loops over the loopback test log files
for logfile in /root/tsimetkosk/loopback_results/*.log; do

  #Removes the file path from the variable
  switch_location_log="${logfile##*/}"

  #Removes '.log' from the variable
  switch_location_only="${switch_location_log%.log}"

  #Checks if all 256 lanes passed the loopback test, prints results if it failed
  if grep -q "Num passing lanes: 256" "$logfile"; then
    echo
    echo " --------------------------------------------------------------"
    printf '\e[1;32m%-6s\e[m\n' "|                        $switch_location_only: PASSED                   |"
    echo " --------------------------------------------------------------"
    echo
  else
    echo
    echo " --------------------------------------------------------------"
    printf '\e[1;31m%-6s\e[m\n' "|                        $switch_location_only: FAILED                   |"
    echo " --------------------------------------------------------------"
    sed -n '/SerDes testing complete/,/Num failing lanes:/p' "$logfile"
    echo
  fi
done | tee /root/tsimetkosk/loopback_results/results

