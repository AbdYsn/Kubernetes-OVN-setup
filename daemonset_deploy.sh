#!/bin/bash

set -e
set -x

exec 1> >(logger -s -t $(basename $0)) 2>&1

while test $# -gt 0; do
  case "$1" in

   --help | -h)
      echo "
daemonset_deploy.sh [options]: deploy the daemonsets of the sriov device plugin and the multus.

"
      exit 0
      ;;
   
   *)
      echo "No such option!!"
      echo "Exitting ...."
      exit 1
  esac
done


deploy_components(){
   if [[ -d yaml/ ]]
   then
      cd yaml/
      
      kubectl create -f sriov-setup.yaml
      kubectl create -f sriovdp-daemonset.yaml
      kubectl create -f multus-daemonset.yaml
      kubectl create -f sriov-net.yaml
    else
        exit 1
   fi

}
deploy_components