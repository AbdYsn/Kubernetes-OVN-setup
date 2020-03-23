#!/bin/bash

#set -e
set -x

interface=""
host_ip=""
netmask=""
bond=""
bond_mode="4"
bond_miion="100"
bond_updelay="12000"
bond_downdelay="0"
bond_master=""

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

   --ip)
      host_ip=$2
      shift
      shift
      ;;

   --netmask)
      netmask=$2
      shift
      shift
      ;;

   --bond)
      bond=$2
      shift
      shift
      ;;

   --bond-mode)
      bond_mode=$2
      shift
      shift
      ;;

   --bond-miion)
      bond_miion=$2
      shift
      shift
      ;;

   --bond-updelay)
      bond_updelay=$2
      shift
      shift
      ;;

   --bond-downdelay)
      bond_downdelay=$2
      shift
      shift
      ;;

   --bond-master)
      bond_master=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
interface_prepare.sh -i <interface> --ip <ip> --netmask <netmask>: A script "\
"to configure an interface using the network service.

options:
 
	--interface | -i) <interface>		The name of the interface "\
"to be configured.
   
	--ip) <wanted ip>			The ip of the master node.

	--netmask) <netmask>			The netmask to be configured "\
"on the interface.

	--bond) <bond mode>			An optional flag to configure the interface as either a bond master or a bond slave. The bond master can be configured more using the options: --bond-mode, --bond-miion, --bond-updelay, --bond-downdelay. The bond slave can be configured using the option --bond-master.

	--bond-mode) <bond mode>		Defaulted to 4 (active-active) mode.

	--bond-miion) <bond miion>		Defaulted to 100.

	--bond-updelay) <bond up delay>		Defaulted to 12000.

	--bond-downdelay) <bond down delay>	defaulted to 0.

	--bond-master) <master interface name>	In case the interface is configured to be a slave interface, this option sets its master.

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

if [[ -z $netmask ]]
then
   echo "The netmask was not provided !!!
   Please provide one using the option --netmask
   for more informaton see the help menu --help or -h
   Exiting ...."
   exit 1
fi

if [[ -z "$host_ip" ]]
then
   host_ip=`ifconfig $interface | grep -o "inet [0-9.]* " | cut -d" " -f 2`
fi

if [[ -z "$host_ip" ]]
then
   echo "no ip on the provided interface, please make sure that the network\
    settings are correct !!!
   Please provide one using the option --interface.
   for more informaton see the help menu --help or -h
   Exiting ...."
   exit 1
fi


##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


check_interface(){
   local_interface=$1

   if [[ ! -d /sys/class/net/"$local_interface" ]]
   then
      echo "ERROR: No interface named $local_interface exist on the machine, "\
           "please check the interface name spelling, or make sure that the "\
           "interface really exist."
      echo "Exiting ...."
      exit 1
   fi
}

common_configs(){
local_interface=$1
   cat << EOF > $conf_file
DEVICE=$local_interface
ONBOOT=yes
NM_CONTROLLED=no
EOF
}

ip_configs(){
   local_ip=$1
   local_netmask=$2

   cat << EOF >> $conf_file
IPADDR=$local_ip
NETMASK=$local_netmask
BOOTPROTO=static
EOF
}

bond_master_configs(){
local_mode=$1
local_miimon=$2
local_updelay=$3
local_downdelay=$4

   cat << EOF >> $conf_file
TYPE=Bond
BONDING_OPTS="mode=$local_mode miimon=$local_miimon updelay=$local_updelay downdelay=local_downdelay"
DEFROUTE=yes
IPV6INIT=no
USERCTL=no
EOF
}

bond_slave_configs(){
local_interface=$1
local_master=$2
   cat << EOF >> $conf_file
BOOTPROTO=none
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$local_interface
MASTER=$local_master
SLAVE=yes
EOF
}


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


conf_file=/etc/sysconfig/network-scripts/ifcfg-"$local_interface"

check_interface $interface
common_configs $interface
ip_configs $host_ip $netmask
systemctl restart network

