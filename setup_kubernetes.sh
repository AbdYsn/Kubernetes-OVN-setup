#!/bin/bash

set -e
set -x

token=""
hostname=""
hostip=""
no_deps="false"
docker_image="docker.io/shaharklein/ovn-kube-u:f4dcb3e1"
net_cidr="192.168.0.0/16" 
svc_cidr="10.90.0.0/16"
host_gateway=""
exec 1> >(logger -s -t $(basename $0)) 2>&1


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

   --interface)
      interface=$2
      shift
      shift
      ;;

   --gateway)
      host_gateway=$2
      shift
      shift
      ;;

   --hostname)
      hostname=$2
      shift
      shift
      ;;

   --docker-image)
      docker_image=$2
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
 
  --token| -t) <cluster token>		An option to indicate that this is a worker host, so that it will join 
					<ca_cert_hash>       a cluster instead of creating one, pass to it the master token and the 
                                    ca_cert_hash.
   
   --hostname) <cluster hostname>	The hostname to use for the cluster creating

   --ip) <ip of cluster admin>		The ip of the master host

   --interface)                     the interface to the cluster

   --gateway)                       the gateway of the network

   --no-deps)				            Do not install the dependencies, use this only if you have ran the 
					                     command before

   --docker-image)                  the image to use to create the ovn containers

   --svc-cidr)                      the service ip to use for the cluster

   --net-cidr)                      the pod network cidr to use for the cluster

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


if [[ -z $hostname ]]
then
   logger "The hostname was not provided !!!
   Will use the machine hostname
   you can provide one using the option --hostname"
   hostname=`hostname -f`
   logger "the hostname that will be used is: $hostname"
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
else
   if [[ -z $hostip ]]
   then
      echo "The ip address was not provided !!!
      Please provide one using the option --ip
      for more informaton see the help menu --help or -h
      Exitting ...."
      exit 1
   fi

   if [[ -z $interface ]]
   then
      echo "The interface was not provided !!!
      Please provide one using the option --interface
      for more informaton see the help menu --help or -h
      Exitting ...."
      exit 1
   fi

   if [[ -z $gateway ]]
   then
      echo "The gateway was not provided !!!
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

   if [[ ! -d $HOME/nv-k8s-sriov-deploy ]]
   then
      git clone https://github.com/shahar-klein/nv-k8s-sriov-deploy.git $HOME/nv-k8s-sriov-deploy
   fi

   check_dir $HOME/nv-k8s-sriov-deploy "failed to get nv-k8s-sriov-deploy"
}

kubernetes_install(){ 
   yum -y install kubelet apt-transport-https ca-certificates curl software-properties-common \
   python3-pip virtualenv python3-setuptools kubeadm
   systemctl enable kubelet
   systemctl start kubelet

   error_check "kubelet --version" "kubelet not running"
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

ovn_cni_setup(){
   if [[ ! -d $HOME/ovn-kubernetes/ ]]
   then
      cd $HOME
   	git clone https://github.com/ovn-org/ovn-kubernetes.git 
   fi

   check_dir $HOME/ovn-kubernetes/ "could not find ovn-kubernetes dir"

   cd $HOME/ovn-kubernetes/
   git checkout 7ae417ea9922bad43c2d575e39e2ebae9962d2a5
   cd go-controller/
   make 
   make install 
   echo "{\"cniVersion\":\"0.3.1\", \"name\":\"ovn-kubernetes\", \"type\":\"ovn-k8s-cni-overlay\"}" > /etc/cni/net.d/10-ovn-kubernetes.conf
   systemctl restart kubelet
}

deploy_components(){
   if [[ -d $HOME/ovn-kubernetes/dist/yaml/ ]]
   then
      file_configuration
      cd $HOME/ovn-kubernetes/dist/yaml/
      kubectl create -f ovn-setup.yaml
      sleep 1
      kubectl create -f ovnkube-db.yaml
      sleep 1
      kubectl create -f ovnkube-master.yaml
      sleep 1
      kubectl create -f ovnkube-node.yaml
   else 
      exit 1
   fi

   if [[ -d $HOME/nv-k8s-sriov-deploy ]]
   then
      cd $HOME/nv-k8s-sriov-deploy
      sleep 1
      kubectl create -f sriov-setup.yaml
      sleep 1
      kubectl create -f sriovdp-daemonset.yaml
      sleep 1
      kubectl create -f multus-daemonset.yaml
      sleep 1
      kubectl create -f sriov-net.yaml
   fi

}

file_configuration(){
      cd $HOME/ovn-kubernetes/dist/images
      make centos
      ./daemonset.sh --image=$docker_image --net-cidr=$net_cidr --svc-cidr=$svc_cidr\
                     --gateway-mode="shared"  --k8s-apiserver="https://$hostip:6443"
      cd ../yaml/
      comment_ovs
      gateway_opt_line=`awk '/OVN_GATEWAY_OPTS/{ print NR; exit }' ovnkube-node.yaml`
      gateway_opt_value_line=$((gateway_opt_line+=1))
      sed -i "$gateway_opt_value_line s/value: \"\"/value: \"--gateway-interface=$interface --gateway-nexthop=$host_gateway\"/"\
      /root/ovn-kubernetes/dist/yaml/ovnkube-node.yaml
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

comment_ovs(){
   lines=`awk -F "" 'BEGIN {
   level=0
   ovs_level=-1
   start_line=-1
   end_line=-1
   skip=1
   }
   {
   level=0
   skip=1
   for (i=1; i<=NF; i++){
         if($i == " "){
                  level++
         }
         else if ($i != "\n"){
                  skip=-1
                  break
         } else
         {
                  break
         }
   }
   if (skip>0){
         next
   }
   if (level <= ovs_level && end_line<=0){
         end_line=NR-1
   }
   if ( match($0, ".*ovs-daemon.*") != 0 && $1 != "#")
   {
         ovs_level=level
         start_line=NR
   }
   }
   END {
   if(end_line == -1 && start_line!=-1){
   end_line=NR
   }
   print start_line "," end_line}
   ' ovnkube-node.yaml`
   if [[ "$lines" != "-1,-1" ]]
   then
      sed -i "$lines s/^/#/" ovnkube-node.yaml
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
ovn_cni_setup

if [[ -z $token ]]
then
   deploy_components
fi
