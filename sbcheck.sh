#!/bin/bash

## Clear old clush groups if they exist
[ -f /etc/dsh/group/nosb ] && rm /etc/dsh/group/nosb
[ -f /etc/dsh/group/sb ] && rm /etc/dsh/group/sb


## Check if SB is enabled 
while read -r switch_cmdline; do
    if [[ "$switch_cmdline" == *"sec_boot=1"* ]]; then
        echo "$switch_cmdline" | cut -d: -f1 >>/etc/dsh/group/sb
    elif [[ "$switch_cmdline" == *"sec_boot=0"* ]]; then 
        echo "$switch_cmdline" | cut -d: -f1 >>/etc/dsh/group/nosb
    fi
done < <((clush -w $(cnodes --platform-controller | nodeset -f) "cat /proc/cmdline"))



## Display the switch groups  
if [[ ! -f /etc/dsh/group/nosb ]]; then
    echo "All switches have secure boot enabled. Do not attempt to flash non-secure uboot file."
    exit 0
fi

if [[ -f /etc/dsh/group/sb ]]; then 
    echo "The following switches have secure boot enabled:"
    cat /etc/dsh/group/sb
    echo ""
fi 

if [[ -f /etc/dsh/group/nosb ]]; then 
    echo "The following switches do NOT have secure boot enabled:"
    cat /etc/dsh/group/nosb
    echo ""
fi 



## Flash the switches if needed
read -p "Flash the uboot on switches that need it? (y/n): " -n 1 answer
case $answer in
    [yY])
        echo ""
        echo "Moving files onto the pC..."
        clush -B -g pdsh:nosb -c /opt/clmgr/tftpboot/u-boot_sc_ros2_2.1-39-g18f5acd7ded.rcw-95ec6.atf-7fbb5.bin /opt/clmgr/tftpboot/pc.itb --dest=/tmp/

        echo "Flashing latest uboot..."
        clush -g pdsh:nosb "uboot_sc_flasher -F /tmp/u-boot_sc_ros2_2.1-39-g18f5acd7ded.rcw-95ec6.atf-7fbb5.bin"

        echo "Flashing latest boot image..."
        clush -g pdsh:nosb "emmc-setup -B;mv /tmp/pc.itb /boot/a.itb;echo -n A > /dev/mmcblk0p1;emmc-setup -b"

        echo "Sending reboot signal to all switches installed in the rack..."
        clush -g pdsh:pc "reboot"
        exit 0;;

    [nN])
        echo ""
        echo "Exiting..."
        exit 0;;
esac
