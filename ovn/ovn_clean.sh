#!/bin/bash

set -e


repo_path=$HOME/ovn-kubernetes/
cni_path='/etc/cni/net.d/10-ovn-kubernetes.conf'

##################################################
##################################################
##################   input   #####################
##################################################
##################################################


while test $# -gt 0; do
  case "$1" in
   --repo-path)
      repo_path=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
ovn_clean.sh: Clean the ovn CNI daemonsets and remove its related directories.

	--repo-path)			An option to specify the path for the ovn-kubernetes repo location file location.

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


delete_repo(){
   if [[ -d $repo_path ]]
   then
      rm -rf $repo_path
   fi

}

remove_cni_file(){
   if [[ -f "$cni_path" ]]
   then
      rm -f "$cni_path" 
   fi

   multus_delgates="$(grep -o -E '"delegates": \[.*\]' /etc/cni/net.d/00-multus.conf | grep ovn-kubernetes)"

   if [[ -n "multus_delgates" ]]
   then
      sed -i 's/"delegates": \[.*\]/"delegates": []/' /etc/cni/net.d/00-multus.conf
   fi

}


##################################################
##################################################
##############   validation   ####################
##################################################
##################################################




##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


if kubectl version 2>/dev/null;
then
   kubectl delete namespace ovn-kubernetes
fi
delete_repo
remove_cni_file
