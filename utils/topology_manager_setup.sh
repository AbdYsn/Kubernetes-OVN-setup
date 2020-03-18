#!/bin/bash

set -e


interface=""
cpus=""
policy=""
kubelet_config_file='/var/lib/kubelet/config.yaml'

##################################################
##################################################
##################   input   #####################
##################################################
##################################################


while test $# -gt 0; do
  case "$1" in

   --policy)
      policy=$2
      shift
      shift
      ;;

   --cpus)
      cpus=$2
      shift
      shift
      ;;

   --interface)
      interface=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
topology_manager_setup.sh --policy <policy> [options]: configure the topology manager policy of the kubelet.

options:

	--policy)		The topology manager policy to configure, it can be one of four values: none, best-effort, restricted, or single-numa-node.

	--cpus)			Comma seperated list of cpus to reserve for the kubelet, it can also be set to auto (in this case the interface must be specified) the script will try to reserve the cpus that are on different numas from the interface numa.

	--interface)		In case of cpus being set to auto, use the interface to match the NUMA on.

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


get_kubelet_cpus(){
   numa_number="$(cat /sys/class/net/$interface/device/numa_node)"
   if [[ -z "$numa_number" ]]
   then
      echo "couldn't find a numa from the interface, make sure the interface exist"
      echo "Exiting...."
      exit 1
   fi
   cpus=$(lscpu -p=cpu,node -y | grep "[0-9]"$ |grep -v "$numa_number"$ | cut -d , -f 1 | xargs | sed 's/ /,/g')
}

set_kubelet_policy(){
   change_value "$kubelet_config_file" "featureGates" ""
   change_value "$kubelet_config_file" "  TopologyManager" "True"
   change_value "$kubelet_config_file" "topologyManagerPolicy" "$policy"
   change_value "$kubelet_config_file" "cpuManagerPolicy" "static"
}

restart_kubelet(){
   if [[ "$(systemctl is-active kubelet)" == "active" ]]
   then
      rm -f /var/lib/kubelet/cpu_manager_state
      systemctl restart kubelet
      if [[ "$(systemctl is-active kubelet)" != "active" ]]
      then
         echo "an error encountered while restarting the kubelet service!"
         echo "Exiting...."
         exit 1
      fi
   fi
}

change_value(){
   file=$1
   wanted_variable=$2
   wanted_value=$3
   if [[ ! -f "$file" ]]
   then
      echo "no such file $file"
      echo "Exiting ..."
      exit 1
   fi
   sed -i "/^$wanted_variable:/d" "$file"
   echo "$wanted_variable: $wanted_value" >> "$file"
}


##################################################
##################################################
##############   validation   ####################
##################################################
##################################################


if [[ -z "$policy" ]]
then
   echo "No policy found, please provide one using the --policy option !!"
   echo "Exiting...."
   exit 1
elif [[ ! "$policy" =~ ^(none|best-effort|restricted|single-numa-node)$ ]]
then
   echo "Unknow policy $policy!! please use one of {none, best-effort, restricted, single-numa-node}"
   echo "Exiting...."
   exit 1
fi

if [[ "$cpus" == "auto" ]]
then
   if [[ -z "$interface" ]]
   then
      echo "The cpus are set to auto, but no interface provided, please provide one using the --interface option."
      echo "Exiting...."
      exit 1
   fi
fi


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


if [[ "$cpus" == "auto" ]]
then
   get_kubelet_cpus
fi

set_kubelet_policy

if [[ -n "$cpus" ]]
then
   change_value "$kubelet_config_file" "reservedSystemCPUs" "$cpus"
else
   sed -i "/^reservedSystemCPUs:/d" "$kubelet_config_file"
fi

restart_kubelet

echo "Please reboot the machine for the effets to take full effect."

