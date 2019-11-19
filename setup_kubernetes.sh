#!/bin/bash

set -e
set -x

interface=""
num_vf=""
token=""
hostname=""
hostip=""
no_deps="false"
ca_hash=""


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

   --num-vf| -v)
      num_vf=$2
      shift
      shift
      ;;

   --token| -t)
      token=$2
      ca_hash=$3
      shift
      shift
      shift
      ;;

   --hostname)
      hostname=$2
      shift
      shift
      ;;

   --ip)
      hostip=$2
      shift
      shift
      ;;
   
   --no-deps)
      no_deps="true"
      shift
      ;;

   --help | -h)
      echo "
setup_offload [options]: set up a kubernetes kubeadm environment with offloading enabled on the host machine.

options:
 
--interface | -i) <interface>		Specify the interface to enable the offloading on.

   --num-vf| -v) <vfs number>		Specify the number of vfs to be created on the interface

   --token| -t) <cluster token>		An option to indicate that this is a worker host, so that it will join 
					a cluster instead of creating one, pass to it the path to the cluster
					token.
   
   --hostname) <cluster hostname>	The hostname to use for the cluster creating

   --ip) <ip of cluster admin>		The ip of the admin host (master)

   --no-deps)				Do not install the dependencies, use this only if you have ran the 
					command before

"
      exit 0
      ;;
   
   *)
      echo "No such option!!"
      echo "Exitting ...."
      exit 1
  esac
done

##################################################
##################################################
##############   validation   ####################
##################################################
##################################################

if [[ -z $interface ]]
then
   echo "No interface was provided !!!"
   echo "Please provide one using the option --interface or -i"
   echo "for more informaton see the help menu --help or -h"
   echo "Exitting ...."
   exit 1
fi

if [[ -z $num_vf ]]
then
   echo "The number of vfs was not provided !!!"
   echo "Please provide one using the option --num_vf or -v"
   echo "for more informaton see the help menu --help or -h"
   echo "Exitting ...."
   exit 1
fi

if [[ -z $hostname ]]
then
   echo "The hostname was not provided !!!"
   echo "Will use the machine hostname"
   echo "you can provide one using the option --hostname"
   hostname=`hostname -f`
   echo "the hostname that will be used is: $hostname"
fi

if [[ -z $hostip ]]
then
   echo "The ip address was not provided !!!"
   echo "Please provide one using the option --ip"
   echo "for more informaton see the help menu --help or -h"
   echo "Exitting ...."
   exit 1
else
   if [[ -z "`cat /etc/hosts | grep $hostname`" ]]
   then
      echo "$hostip $hostname" >> /etc/hosts
   fi 
fi

if [[ -n token ]]
then 
   if [[ -z ca_hash ]]
   then 
      echo "a token to join the cluster was provided \
            but no ca_cert hash was provided, please provide\
            one, EXITTING ....."
      exit 1
   fi
fi

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################



golang_install(){
   yum install wget  git -y
  
   echo "installing golang"
   wget https://dl.google.com/go/go1.12.12.linux-amd64.tar.gz
   tar -C /usr/local -xzf go1.12.12.linux-amd64.tar.gz
   
   check_dir /etc/cni/net.d/
   check_dir /opt/cni/bin/
   check_dir /root/go/src/github.com/
}

check_dir(){
   if [[ ! -d $1 ]]
   then
      mkdir -p $1
   fi 
}

cnis_install(){
   if [[ ! -d $GOPATH/src/github.com/containernetworking/plugins ]]
   then
      git clone https://github.com/containernetworking/plugins $GOPATH/src/github.com/containernetworking/plugins
      $GOPATH/src/github.com/containernetworking/plugins/build_linux.sh
      cp $GOPATH/src/github.com/containernetworking/plugins/bin/* /opt/cni/bin 
   fi

   if [[ ! -d $GOPATH/src/github.com/intel/sriov-cni ]]
   then
      git clone https://github.com/intel/sriov-cni $GOPATH/src/github.com/intel/sriov-cni
      cd $GOPATH/src/github.com/intel/sriov-cni
      make build
   fi

   if [[ ! -d $GOPATH/src/github.com/intel/sriov-network-device-plugin ]]
   then
      git clone https://github.com/intel/sriov-network-device-plugin $GOPATH/src/github.com/intel/sriov-network-device-plugin
   fi
}

kubernetes_install(){ 
   yum -y install kubelet apt-transport-https ca-certificates curl software-properties-common python3-pip virtualenv python3-setuptools kubeadm
}

docker_install(){
   yum install -y yum-utils device-mapper-persistent-data lvm2 mstflint bind-utils
   yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
   
   yum install -y docker-ce docker-ce-cli containerd.io
   systemctl enable docker
   systemctl start docker
}

init_kubadmin(){
   if [[ `systemctl is-enabled openvswitch` ]]
   if [[ -z $token ]]
   then 
   	kubeadm init --apiserver-advertise-address=$hostip --node-name=$hostname  --skip-phases addon/kube-proxy --pod-network-cidr 192.168.0.0/16 --service-cidr 10.90.0.0/16
      export KUBECONFIG=/etc/kubernetes/admin.conf
      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config
   else
      kubeadm join "$hostip:6443" --token $token --discovery-token-ca-cert-hash $ca_hash 
   fi
}

ovn_cni_setup(){
   echo "installing kubernetes ovn cni"
   cd $HOME
   git clone https://github.com/ovn-org/ovn-kubernetes.git 
   cd ovn-kubernetes/
   git checkout 8ea23e02f2852372f42560f25fe54b73180e0d03
   cd go-controller/
   make 
   make install 
   echo "{\"cniVersion\":\"0.3.1\", \"name\":\"ovn-kubernetes\", \"type\":\"ovn-k8s-cni-overlay\"}" > /etc/cni/net.d/10-ovn-kubernetes.conf
   systemctl restart kubelet
}

firewall_allow(){
   # the first inout is the protocol and the second input is the port
   sudo iptables -I INPUT 1 -p $1 --dport $2 -j ACCEPT
}

firewall_handling(){
   systemctl stop firewalld
   systemctl disable firewalld
}

hostname_change(){
hostnamectl set-hostname $hostname
}

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


if [[ $no_deps == "false" ]]
then
   golang_install
   source ~/.bashrc
   cnis_install
   kubernetes_install
   docker_install
fi

hostname_change
firewall_handling
enable_switchdev
init_kubadmin
ovn_cni_setup



