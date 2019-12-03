#!/bin/bash

set -e
set -x

parse_conf(){
   param=$1
   if [[ -f local.conf ]]
   then
      echo `grep $param local.conf | cut -d"=" -f 2`
   fi
}

hostip=parse_conf master_ip
hostname=parse_conf master_hostname
token=parse_conf token
ca_hash=parse_conf ca_hash
net_cidr=parse_conf net_cidr
svc_cidr=parse_conf svc_cidr

no_deps="false"


##################################################
##################################################
##################   input   #####################
##################################################
##################################################

while test $# -gt 0; do
  case "$1" in

   --token| -t)
      token=$2
      ca_hash=$3
      shift
      shift
      shift
      ;;
   
   --ip)
      hostip=$2
      shift
      shift
      ;;

   --hostname)
      hostname=$2
      shift
      shift
      ;;
      
   --svc-cidr)
      svc_cidr=$2
      shift
      shift
      ;;

   --net-cidr)
      net_cidr=$2
      shift
      shift
      ;;
   
   --no-deps)
      no_deps="true"
      shift
      ;;

   --help | -h)
      echo "
setup_kubernetes.sh [options]: set up a kubernetes kubeadm environment with offloading enabled on the host machine.

options:
 
	--token| -t) 	<cluster token>			An option to indicate that this is a worker host, so that it will join 
			<ca_cert_hash>			a cluster instead of creating one, pass to it the master token and the 
							ca_cert_hash.
   
	--hostname) <cluster hostname>			The hostname to use for the cluster creating

	--ip) <ip of cluster admin>			The ip of the master host

	--no-deps)					Do not install the dependencies, use this only if you have ran the 
							command before

	--svc-cidr)					The service ip to use for the cluster

	--net-cidr)					The pod network cidr to use for the cluster

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


if [[ -z $hostname ]]
then
   logger "The hostname was not provided !!!
   Will use the machine hostname
   you can provide one using the option --hostname"
   hostname=`hostname -f`
   logger "the hostname that will be used is: $hostname"
fi

if [[ -n $token ]]
then 
   if [[ -z $ca_hash ]]
   then 
      echo "a token to join the cluster was provided \
            but no ca_cert hash was provided, please provide\
            one, EXITTING ....."
      exit 1
   fi
else
   if [[ -z $hostip ]]
   then
      echo "The ip address was not provided !!!
      Please provide one using the option --ip
      for more informaton see the help menu --help or -h
      Exitting ...."
      exit 1
   fi
fi


##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################



golang_install(){
   logger "installing go"
   yum install wget  git -y
   if [[ -z "`go version`" ]]
   then
      wget https://dl.google.com/go/go1.12.12.linux-amd64.tar.gz
      tar -C /usr/local -xzf go1.12.12.linux-amd64.tar.gz
   fi

   mkdir -p /etc/cni/net.d/
   mkdir -p /opt/cni/bin/
   mkdir -p /root/go/src/github.com/

   check_dir /usr/local/go "failed to extract the golang"
}

cnis_install(){
   logger "getting the cnis and installing them"
   if [[ ! -d $GOPATH/src/github.com/containernetworking/plugins ]]
   then
      git clone https://github.com/containernetworking/plugins $GOPATH/src/github.com/containernetworking/plugins
      $GOPATH/src/github.com/containernetworking/plugins/build_linux.sh
      cp $GOPATH/src/github.com/containernetworking/plugins/bin/* /opt/cni/bin 
   fi

   check_dir $GOPATH/src/github.com/containernetworking/plugins "failed to install containernetworking"

   if [[ ! -d $GOPATH/src/github.com/intel/sriov-cni ]]
   then
      git clone https://github.com/intel/sriov-cni $GOPATH/src/github.com/intel/sriov-cni
      cd $GOPATH/src/github.com/intel/sriov-cni
      make build
   fi

   check_dir $GOPATH/src/github.com/intel/sriov-cni "failed to install sriov-cni"

   if [[ ! -d $GOPATH/src/github.com/intel/sriov-network-device-plugin ]]
   then
      git clone https://github.com/intel/sriov-network-device-plugin $GOPATH/src/github.com/intel/sriov-network-device-plugin
   fi

   check_dir $GOPATH/src/github.com/intel/sriov-network-device-plugin "failed to install sriov-network-device-plugin"

   #if [[ ! -d $HOME/nv-k8s-sriov-deploy ]]
   #then
   #   git clone https://github.com/shahar-klein/nv-k8s-sriov-deploy.git $HOME/nv-k8s-sriov-deploy
   #fi

   #check_dir $HOME/nv-k8s-sriov-deploy "failed to get nv-k8s-sriov-deploy"
}

kubernetes_install(){ 
   yum -y install kubelet apt-transport-https ca-certificates curl software-properties-common \
   python3-pip virtualenv python3-setuptools kubeadm
   systemctl enable kubelet
   systemctl start kubelet

   error_check "kubelet --version" "kubelet not installed"
   error_check "kubeadm version" "kubeadm not installed"    
}

docker_install(){
   yum install -y yum-utils device-mapper-persistent-data lvm2 mstflint bind-utils
   yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
   
   yum install -y docker-ce docker-ce-cli containerd.io
   systemctl enable docker
   systemctl start docker

   error_check "docker version" "docker is not installed correctlly"
}

init_kubadmin(){
   if [[ `systemctl is-enabled openvswitch` == "disabled" ]]
   then
      systemctl enable openvswitch
   fi

   if [[ `systemctl is-active openvswitch` == "inactive" ]]
   then
      systemctl start openvswitch
   fi

   sleep 1

   if [[ `systemctl is-active openvswitch` == "inactive" ]]
   then
      exit 1
   fi

   if [[ -z $token ]]
   then 
   	kubeadm init --apiserver-advertise-address=$hostip --node-name=$hostname  --skip-phases addon/kube-proxy --pod-network-cidr $net_cidr --service-cidr $svc_cidr
      export KUBECONFIG=/etc/kubernetes/admin.conf
      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config
      error_check "kubectl cluster-info" "The cluster was not created"
   else
      kubeadm join "$hostip:6443" --token $token --discovery-token-ca-cert-hash $ca_hash
      #cluster joining varification
   fi
}

check_dir(){
   dir=$1
   error_msg=$2
   if [[ ! -d $dir ]]
      then
         logger $error_msg
         exit 1
      fi
}

error_check(){
   check_command=$1
   err_msg=$2
   dummy=`$check_command`
   if [[ $? -ne 0 ]]
   then
      logger $err_msg
      exit 1
   fi 
}


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


if [[ $no_deps == "false" ]]
then
   golang_install
   cnis_install
   kubernetes_install
   docker_install
fi

init_kubadmin

if [[ -z $token ]]
then
   kubeadm token create --print-join-command   
fi
