#!/bin/bash

set -e

new_hostname=""
host_ip=""

old_hostname=`hostname -f`


##################################################
##################################################
##################   input   #####################
##################################################
##################################################


while test $# -gt 0; do
  case "$1" in

   --new-hostname | -n)
      new_hostname=$2
      shift
      shift
      ;;

   --host-ip)
      host_ip=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
change_hostname.sh -n <new hostname>: A script to change the 

options:
 
	--new-hostname | -n) <hostname>		The new hostname wanted for the machine.
   
	--host-ip) <IP address>			The IP address to associate with the new hostname. This is added to the /etc/hosts file.

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


change_hostname(){
if [[ "$old_hostname" != "$new_hostname" ]]
then
   hostnamectl set-hostname $new_hostname
   if [[ `echo $?` != "0" ]]
   then
      echo "Failed to set the hostname."
      echo "Exiting...."
      exit 1
   fi
fi
}

hostname_add(){
   local_ip=$1
   local_hostname=$2
   if [[ -n "`grep "$local_ip" /etc/hosts`" ]]
   then
      sed -i "/$local_ip/d" /etc/hosts
   fi
   echo "$local_ip $local_hostname" >> /etc/hosts
}


##################################################
##################################################
##############   validation   ####################
##################################################
##################################################


if [[ -z "$new_hostname" ]]
then
   echo "No new name was provided, please provide one using \
the --new-hostname or -n options."
   echo "Exiting...."
   exit 1
fi

if [[ -z "$host_ip" ]]
then
   echo "No ip was provided, please provide one using \
the --host-ip option."
   echo "Exiting...."
   exit 1
fi


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


change_hostname

if [[ -n "$host_ip" ]]
then
   hostname_add "$host_ip" "$new_hostname"
fi

echo "You have to restart the session(logout and then log in) for the changes to take effect."
