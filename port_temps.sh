#!/bin/bash 

clush -L -w $(cnodes --switch-controller) 'echo "Port Temperature Readings:"; for j in {1..24}; do echo -n "Port ${j}: "; cat /chfs/switch/v0/sensors/Temperature/transceiver${j}/ReadingCelsius; done'
