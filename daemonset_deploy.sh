#!/bin/bash

set -e
set -x

parse_conf(){
   param=$1
   if [[ -f local.conf ]]
   then
      echo `grep -x $param"=.*" local.conf | cut -d"=" -f 2 -s`
   fi
}

interface=`parse_conf interface`

while test $# -gt 0; do
  case "$1" in

   --interface | -f)
     interface=$2
     shift
     shift
     ;;

   --help | -h)
      echo "
daemonset_deploy.sh [options] --interface <interface>: deploy the daemonsets "\
"of the sriov device plugin and the multus.

	--interface | -i) <interface>	The interface to use for SRIOV.

"
      exit 0
      ;;
   
   *)
      echo "No such option!!"
      echo "Exiting ...."
      exit 1
  esac
done

exec 1> >(logger -s -t $(basename $0)) 2>&1


##################################################
##################################################
##############   functions    ####################
##################################################
##################################################


check_interface(){
   local_interface=$1

   if [[ -z $local_interface ]]
   then
      echo "ERROR: no interface was provided, please provide one using the "\
           "--interface option."
      echo "Exiting ...."
      exit 1
   fi

   if [[ ! -d /sys/class/net/"$local_interface" ]]
   then
      echo "ERROR: No interface named $local_interface exist on the machine, "\
           "please check the interface name spelling, or make sure that the "\
           "interface really exist."
      echo "Exiting ...."
      exit 1
   fi

   if [[ "`cat /sys/class/net/$local_interface/device/sriov_numvfs`" == "0" ]]
   then
      echo "ERROR: Interface $local_interface has no vfs, please create some "\
           "and try again."
      echo "Exiting ...."
      exit 1
   fi
}

set_sriov_device(){
   local_interface=$1
   device="`cat /sys/class/net/$local_interface/device/sriov_vf_device`"
   device_line_number=`awk "/device/ {print NR}" sriov-setup.yaml`
   sed -i "$device_line_number s/\[.*\]/[$device]/" sriov-setup.yaml
}

deploy_components(){
   if [[ -d yaml/ ]]
   then
      cd yaml/

      set_sriov_device $interface

      kubectl create -f sriov-setup.yaml
      kubectl create -f sriovdp-daemonset.yaml
      kubectl create -f multus-daemonset.yaml
      kubectl create -f sriov-net.yaml
    else
      echo "ERROR: there is no yaml directory in the current working "\
           "directory, please make sure to run the script from the"\
           "Kubernetes-OVN-setup directory."
      echo "Exiting ...."
      exit 1
   fi
}


##################################################
##################################################
##############   validation   ####################
##################################################
##################################################


check_interface "$interface"


##################################################
##################################################
##############      main      ####################
##################################################
##################################################


deploy_components
