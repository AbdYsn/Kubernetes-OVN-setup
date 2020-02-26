#!/bin/bash
set -x

parse_conf(){
   param=$1
   if [[ -f local.conf ]]
   then
      echo `grep -x $param"=.*" local.conf | cut -d"=" -f 2`
   fi
}

interface=`parse_conf interface`
bond_slave1=`parse_conf bond_slave1`
bond_slave2=`parse_conf bond_slave2`
bond_ip=`parse_conf host_ip`

network_service=""
isNM=""

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

    --slave1)
      bond_slave1=$2
      shift
      shift
      ;;

    --slave2)
      bond_slave2=$2
      shift
      shift
      ;;

    --ip)
      bond_ip=$2
      shift
      shift
      ;;

    --help | -h)
      echo "
create_a_bond.sh -i <interface> --slave1 <slave1> --slave2 <slave2> A script to create a bond interface
                 named interface using slave1 and slave2 as parameter. The bond will be in active-active
                 mode.

options:

	--interface | -i)		The bond name to be created.

	--slave1)			Slave1 of the bond.

	--slave2)			Slave2 of the bond.

	--ip)				The ip address of the bond.

"
      exit 0
      ;;
   
   *)
      echo "No such option, please see the help!!"
      echo "Exitting ...."
      exit 1
  esac
done

exec 1> >(logger -s -t $(basename $0 )) 2>&1

##################################################
##################################################
###############  Validations  ####################
##################################################
##################################################

if [[ -z `ls /sys/class/net/ | grep $slave1` ]]
then
   echo "Error: Slave1: No device with net name $slave1
, Please choose an existting net device for slave1!"
   exit 1
fi

if [[ -z `ls /sys/class/net/ | grep $slave2` ]]
then
   echo "Error: Slave2: No device with net name $slave2
, Please choose an existting net device for slave2!"
   exit 1
fi

if [[ -z "$bond_ip" ]]
then
   echo "Error: Ip address: the ip address is not configured
, Please provide an ip address"
   exit 1
fi

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################

get_network_service(){
   if [[ `systemctl is-active network` == "active" ]]
   then
      network_service="network"
      isNM="no"
   elif [[ `systemctl is-active NetworkManager` == "active" ]]
   then
      network_service="NetworkManager"
      isNM="yes"
   else
      echo "No suitable network service is active on the machine"
      exit 1
   fi
}

configure_slave_interface(){
   slave_name=$1
   
   file=/etc/sysconfig/network-scripts/ifcfg-$slave_name

   if [[ -n `ifconfig $slave_name` ]]
   then
      ifconfig $slave_name down
   fi

   cat << EOF > $file
TYPE=Ethernet
BOOTPROTO=none
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$slave_name
DEVICE=$slave_name
ONBOOT=yes
MASTER=$interface
SLAVE=yes
NM_CONTROLLED=$isNM
EOF
}

confiugre_bond_interface(){
   file=/etc/sysconfig/network-scripts/ifcfg-$interface

   if [[ -n `ifconfig $interface` ]]
   then
      ifconfig $interface down
   fi

   cat << EOF > $file
DEVICE=$interface
BOOTPROTO=static
ONBOOT=yes
NM_CONTROLLED=$isNM
IPV6INIT=no
USERCTL=no
TYPE=Bond
BONDING_OPTS="mode=4 miimon=100 updelay=12000 downdelay=0"
IPADDR0=$bond_ip
PREFIX0=16
DEFROUTE=yes
EOF   
}

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


get_network_service

configure_slave_interface $slave1
configure_slave_interface $slave2
confiugre_bond_interface

systemctl restart $network_service
