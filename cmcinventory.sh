#!/bin/bash

#Clear out old info and set up before starting discovery process
echo "Removing old hosts..."
rm /root/.ssh/known_hosts
> /opt/clmgr/log/cmcinventory.log &>/dev/null 
#rm /opt/clmgr/log/cmcinventory.log
#touch /opt/clmgr/log/cmcinventory.log

echo "Clearing previous switch locations..."
cm controller delete -c x9000c[1,3]r[0-7]b0 &>/dev/null
cm controller delete -c x9000c[1,3]r[0-7]m0 &>/dev/null

echo "Enabling node discovery..."
cm node discover enable -F -n hostctrl3000 &>/dev/null

#Start the process
echo "Starting cmcinventory process..."
systemctl start cmcinventory
echo "Waiting for cmcinventory process to finish (should take ~6 minutes)..."

#Timer to track elapsed time in the background
(
  start_time=$SECONDS
  while true; do
    echo "Waited $((SECONDS - start_time)) seconds..."
    sleep 30
  done
) &
timer_pid=$! #Tracking the timer's PID to kill later

#Tail the logfile as it builds and exit once the correct string is found
grep -q -m 1 "Compare Inventory CMMs 2, Changed 0" <(tail -f /opt/clmgr/log/cmcinventory.log)
grep_exit_code=$? #grab grep's exit code for use later

#Kill the timer
kill $timer_pid
wait $timer_pid 2>/dev/null

#Check if grep was successful before moving on
if [[ $grep_exit_code -eq 0 ]]; then
  switch_locations=$(cnodes --switch-controller --platform-controller)
  echo
  echo "Successfully found the following locations:"
  printf "%s\n" "$switch_locations"
  echo
elif [[ $grep_exit_code -eq 2 ]]; then
  echo "Logfile at /opt/clmgr/log/cmcinventory.log is missing or inaccesible"
  exit
else
  echo "'grep' failed to parse logfile with exit code $?"
  exit
fi

#Stop the process
systemctl stop cmcinventory

#Disable discovery mode
echo "Disabling discovery mode..."
cm node discover disable &>/dev/null

echo "cmcinventory process complete"

exit
