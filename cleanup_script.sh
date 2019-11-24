#!/bin/bash
set -x

docker_clean="true"
cnis_clean="true"
golang_clean="false"
interface=""
exec 1> >(logger -s -t $(basename $0 )) 2>&1

##################################################
##################################################
##################   input   #####################
##################################################
##################################################

while test $# -gt 0; do
  case "$1" in

    --no-docker)
      docker_clean="false"
      shift
      ;;

    --no-cnis)
      cnis_clean="false"
      shift
      ;;

    --golang)
      golang_clean="true"
      shift
      ;;

    --interface | -i)
      interface=$2
      shift
      shift
      ;;
 
    --help | -h)
      echo "
cleanup_script [options] -i <interface> A script to cleanup the host from kubernetes 

options:

    --no-docker)                do not clean the docker

    --no-cnis)                  do not remove the cnis

    --golang)                   remove the golang

    --interface | -i)           the interface connected to the master node, used to restore the 
                                ip on the interface
                                
"
      exit 0
      ;;
   
   *)
      echo "No such option, please see the help!!"
      echo "Exitting ...."
      exit 1
  esac
done

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


kubernetes_cleanup(){
    kubeadm reset -f 
    rm -rf $HOME/.kube/config
    package_delete kubeadm
    package_delete kubelet
    package_check "kubeadm" "the package kubeadm was not removed"
    package_check "kubelet" "the package kubelet was not removed"
    delete_dir "/etc/kubernetes/"
}

docker_cleanup(){
    package_delete docker
    package_check "docker" "the package docker was not removed"
}

package_delete(){
    packages=`rpm -qa | grep $1`
    if [[ -n $packages ]]
    then
        for package in $packages;
        do
            yum remove $package -y
        done
    fi
}

cnis_cleanup(){
    delete_dir $HOME/ovn-kubernetes/
    
    delete_dir $GOPATH/src/github.com/intel/sriov-network-device-plugin

    delete_dir $GOPATH/src/github.com/intel/sriov-cni

    delete_dir $GOPATH/src/github.com/containernetworking/plugins
}

golang_cleanup(){
    delete_dir /usr/local/go
}

delete_dir(){
    path=$1
    if [[ -d $path ]]
    then
        rm -rf $path
    fi 
    check_dir $path "the path $path was not removed"
}

clean_ovs(){
    if [[ -n "`rpm -qa | grep openvswitch`" ]] 
    then
        rm -rf /var/log/openvswitch/
        rm -rf /var/run/openvswitch/
        rm -rf /var/log/ovn-kubernetes
        rm -rf /etc/openvswitch/conf.db
        systemctl restart openvswitch
        ifdown $interface
        sleep 1
        ifup $interface
    fi
}

check_dir(){
   dir=$1
   error_msg=$2
   if [[ -d $dir ]]
      then
         logger $error_msg
         exit 1
      fi
}

package_check(){
    package=$1
    error_msg=$2
    rpm -qa --quiet | grep $package
    if [[ $? -eq 0 ]]
    then
        logger error_msg
        exit 1
    fi
}

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################

kubernetes_cleanup

if [[ $docker_clean == "true" ]]
then
    docker_cleanup
fi

if [[ $cnis_clean == "true" ]]
then
    cnis_cleanup
fi

if [[ $golang_clean == "true" ]]
then
    golang_cleanup
fi

clean_ovs
