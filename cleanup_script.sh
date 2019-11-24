#!/bin/bash
set -x

docker_clean="true"
cnis_clean="true"
golang_clean="false"
ovs_image=""
interface=""

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

   --ovs-image)
      ovs_image=$2
      shift
      shift
      ;;

   --interface | -i)
      interface=$2
      shift
      shift
      ;;
 
   --help | -h)
      echo "
cleanup_script [options] -i <interface> --ovs-image <ovs-image> A script to cleanup the host from kubernetes 

options:

   --no-docker)             do not clean the docker

   --no-cnis)               do not remove the cnis

   --no-golang)             do not remove the golang

   --ovs-image)             the image for the openVswitch, used to reinstall the ovs

   --interface | -i)        the interface connected to the master node
 
   --help | -h) <interface>		   show the help
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
}

docker_cleanup(){
    package_delete docker
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
   if [[ -d $1 ]]
   then
      rm -rf $1
   fi 
}

interface_delete(){
    if [[ "`systemctl is-active openvswitch`" == "active" ]] && [[ -n $ovs_image ]] 
    then
        if [[ -n "`ovs-vsctl list-br | grep br$interface`" ]]
        then
            if [[ -n "`ovs-vsctl list-ports br$interface | grep $interface`" ]]
            then
                ovs-vsctl del-port "br$interface" $interface
            fi
        fi
        reinstall_ovs
        ifdown $interface
        sleep 1
        ifup $interface
    elif [[ -n $ovs_image ]]
    then
        logger "no ovsImage was provided"
    fi
}

reinstall_ovs(){
    rm -rf /var/log/openvswitch/
    rm -rf /var/run/openvswitch/
    rm -rf /var/log/ovn-kubernetes
    rm -rf /etc/openvswitch/
    yum reinstall -y $ovs_image
    systemctl stop openvswitch
    sleep 1
    systemctl start openvswitch
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

interface_delete
