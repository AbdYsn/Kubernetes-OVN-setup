#!/bin/bash

#set -e
set -x

parse_conf(){
   param=$1
   if [[ -f local.conf ]]
   then
      echo `grep -x $param"=.*" local.conf | cut -d"=" -f 2`
   fi
}

master_ip=`parse_conf master_ip`
master_hostname=`parse_conf master_hostname`
netmask=`parse_conf netmask`
host_ip=`parse_conf host_ip`
hostname=`parse_conf hostname`
interface=`parse_conf interface`
hostname_change_flag=`parse_conf change_machine_hostname`

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

   --hostname)
      hostname=$2
      shift
      shift
      ;;

   --master-hostname)
      master_hostname=$2
      shift
      shift
      ;;

   --ip)
      master_ip=$2
      shift
      shift
      ;;

   --netmask)
      netmask=$2
      shift
      shift
      ;;

   --set-hostname)
      hostname_change_flag="true"
      shift
      ;;

   --help | -h)
      echo "
prepration_script [options] --ip <master ip> --master-hostname <master hostname> --hostname <hostname of host> --netmask <network netmask>\
 --vfs-num <number of vfs to create> --interface <the interface to create the vfs on>: prepare the host by initializing some global\
  variables and setting the hostname.

options:
 
	--interface | -i) <interface>			The name to be used to rename the netdev at the specified pci address.
   
	--hostname) <host hostname>			The hostname of the current host

	--set-hostname)					A flag used if you want to change the hostname of the machine to the specified host name

	--master-hostname) <master hostname>		The hostname of the master

	--ip) <ip of the master node>			The ip of the master node

	--netmask) <netmask>				The cluster network netmask, used to configure the interface.

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
   Exitting ...."
   exit 1
fi

if [[ -z $hostname ]]
then
   logger "The hostname was not provided !!!
   Will use the machine hostname
   you can provide one using the option --hostname"
   hostname=`hostname -f`
   logger "the hostname that will be used is: $hostname"
fi

if [[ -z $master_hostname ]]
then
   echo "The master hostname was not provided !!!
   Please provide one using the option --master-hostname
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

if [[ -z $master_ip ]]
then
   echo "The master ip was not provided !!!
   Please provide one using the option --ip
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

if [[ -z $netmask ]]
then
   echo "The netmask was not provided !!!
   Please provide one using the option --netmask
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

my_path=`pwd`

if [[ -z "$host_ip" ]]
then
   host_ip=`ifconfig $interface | grep -o "inet [0-9.]* " | cut -d" " -f 2`
fi

if [[ -z "$host_ip" ]]
then
   echo "no ip on the provided interface, please make sure that the network\
    settings are correct !!!
   Please provide one using the option --interface
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


change_content(){
   file=$1
   content=$2
   new_value=$3
   amend="$4"
   file_content=`grep $content $file` 
   if [[ -z $file_content ]]
   then
      echo "$content=$new_value" >> $file
   elif [[ `cut -d"=" -f 2 <<< $file_content ` != "$new_value" ]] && [[ -z $amend ]]
   then
      sed -i s/"$content=[^ ]*"/"$content=$new_value"/g $file
   elif [[ ! `cut -d"=" -f 2 <<< $file_content ` =~ $new_value ]] && [[ -n $amend ]]
   then
      old_content=`grep -o "$content=[^ ]*" $file`
      sed -i s/"$old_content"/"$old_content$new_value"/g $file
   fi
}

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


gopath_check
kubernetes_repo_check
echo "Please reboot the host"
