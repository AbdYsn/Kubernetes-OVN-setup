#!/bin/bash

set -e
set -x

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
daemonset_deploy.sh [options]: deploy the daemonsets of the sriov device plugin and the multus.

	--interface | -i)		The main interface for the setup
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

deploy_components(){
   if [[ -d yaml/ ]]
   then
      cd yaml/

      device=`cat /sys/class/net/$interface/device/virtfn0/device | cut -d x -f 2`
      line=`awk "/device/ {print NR}" sriov-setup.yaml`
      sed -i "$line s/\[.*\]/[$device]/" sriov-setup.yaml
      kubectl create -f sriov-setup.yaml
      kubectl create -f sriovdp-daemonset.yaml
      kubectl create -f multus-daemonset.yaml
      kubectl create -f sriov-net.yaml
    else
        exit 1
   fi
}
deploy_components
