#!/bin/bash

set -e

interface=""
new_name=""
pci_address=""


##################################################
##################################################
##################   input   #####################
##################################################
##################################################


while test $# -gt 0; do
  case "$1" in

   --interface | -i)
      interface=$2
      shift
      shift
      ;;

   --new-name | -n)
      new_name=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
interface_rename.sh -i <interface> -n <new name of interface>: A script \
to add a udev rule to rename an interface.

options:
 
	--interface | -i) <interface>		The name of the interface \
to rename.
   
	--n) <new name>				The new name of the interface.

"
      exit 0
      ;;
   
   *)
      echo "No such option!!"
      echo "Exitting ...."
      exit 1
  esac
done

exec 1> >(logger -s -t $(basename $0)) 2>&1

set -x


##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


check_interface_existence(){
   local_interface=$1
   check_type=$2

   if [[ ! -d /sys/class/net/"$local_interface" ]]
   then
      echo "ERROR: No interface named $local_interface exist on the machine, "\
           "please check the interface name spelling, or make sure that the "\
           "interface really exist."
      echo "Exiting ...."
      exit 1
   fi
}

check_interface_absence(){
   local_interface=$1
   
   if [[ -d /sys/class/net/"$local_interface" ]]
   then
      echo "ERROR: An interface named $local_interface already exist on the "\
           "machine, please choose another name"
      echo "Exiting ...."
      exit 1
   fi
}

get_pci_address(){
   pci_address=$(grep PCI_SLOT_NAME /sys/class/net/$interface/device/uevent \
                | cut -d = -f 2 -s)
}

change_interface_name(){   
   if [[ ! -f /etc/udev/rules.d/70-persistent-ipoib.rules ]]
   then
      touch /etc/udev/rules.d/70-persistent-ipoib.rules
   fi

   check_line=`grep $pci_address /etc/udev/rules.d/70-persistent-ipoib.rules | sed 's/\"/\\\"/g' | sed 's/\*/\\\*/g'`
   if [[ -z $check_line ]]
   then
      echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\", KERNELS==\"$pci_address\", NAME:=\"$new_name\"" \
      >> /etc/udev/rules.d/70-persistent-ipoib.rules
   else
      new_line="ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\", KERNELS==\"$pci_address\", NAME:=\"$new_name\""
      sed -i "s/$check_line/$new_line/g" /etc/udev/rules.d/70-persistent-ipoib.rules
   fi
}

change_cfg_name(){
   if [[ -f /etc/sysconfig/network-scripts/ifcfg-"$interface" ]]
   then
      sed -i "s/$interface/$new_name/g" /etc/sysconfig/network-scripts/ifcfg-$interface
      mv /etc/sysconfig/network-scripts/ifcfg-$interface /etc/sysconfig/network-scripts/ifcfg-$new_name
   fi
}


##################################################
##################################################
##############   validation   ####################
##################################################
##################################################


if [[ -z "$interface" ]]
then
   echo "The interface was not provided !!!
   Please provide one using the option --interface
   for more informaton see the help menu --help or -h
   Exiting ...."
   exit 1
fi

if [[ -z $new_name ]]
then
   echo "No new name provided, please provide one using --new-name or -n \
options."
   echo "Exiting...."
   exit 1
fi

check_interface_existence $interface
check_interface_absence $new_name


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


get_pci_address

change_interface_name

change_cfg_name
