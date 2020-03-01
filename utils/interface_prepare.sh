#!/bin/bash

#set -e
set -x

interface=""
host_ip=""
netmask=""


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

interface_ip_config(){
   local_interface=$1
   local_ip=$2
   local_netmask=$3

   conf_file=/etc/sysconfig/network-scripts/ifcfg-$local_interface
   
   cat << EOF > $conf_file
DEVICE=$local_interface
IPADDR=$local_ip
NETMASK=$local_netmask
BOOTPROTO=static
ONBOOT=yes
NM_CONTROLLED=no
EOF
}


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


check_interface $interface
interface_ip_config $interface $host_ip $netmask
systemctl restart network

