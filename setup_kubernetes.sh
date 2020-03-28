#!/bin/bash

set -e
set -x

parse_conf(){
   param=$1
   if [[ -f local.conf ]]
   then
      grep -x $param"=.*" local.conf | cut -d"=" -f 2 -s
   fi
}

interface=`parse_conf interface`
vfs_num=`parse_conf vfs_num`
master_ip=`parse_conf master_ip`
host_ip=`parse_conf host_ip`
netmask=`parse_conf netmask`
master_hostname=`parse_conf master_hostname`
hostname=`parse_conf hostname`
token=`parse_conf token`
ca_hash=`parse_conf ca_hash`
net_cidr=`parse_conf net_cidr`
svc_cidr=`parse_conf svc_cidr`
install_deps=`parse_conf install_deps`
is_master=`parse_conf is_master`
go_version=`parse_conf go_version`
topology_manager=`parse_conf topology_manager`
is_bond=`parse_conf is_bond`
slave1=`parse_conf slave1`
slave2=`parse_conf slave2`

switchdev_scripts_name="switchdev_setup.sh"

go_path='/usr/local/go'


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

   --interface| -i)
      interface=$2
      shift
      shift
      ;;

   --vfs| -v)
      vfs_num=$2
      shift
      shift
      ;;
   
   --master-ip)
      master_ip=$2
      shift
      shift
      ;;

   --host-ip)
      host_ip=$2
      shift
      shift
      ;;
   
   --netmask)
      netmask=$2
      shift
      shift
      ;;

   --master-hostname)
      master_hostname=$2
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
      install_deps="fasle"
      shift
      ;;

   --go-version)
      go_version=$2
      shift
      shift
      ;;

   --topology-manager)
      topology_manager=$2
      shift
      shift
      ;;

   --is-bond)
      is_bond="true"
      shift
      ;;

   --slave1)
      slave1=$2
      shift
      shift
      ;;

   --slave2)
      slave2=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
setup_kubernetes.sh [options]: set up a kubernetes kubeadm environment with offloading enabled on the host machine.

options:
 
	--token| -t) 	<cluster token>			An option to indicate that this is a worker host, so that it will join 
			<ca_cert_hash>			a cluster instead of creating one, pass to it the master token and the 
							ca_cert_hash.
   
	--hostname) <machine hostname>			The hostname of the machine.

	--master-hostname) <master machine hostname>	The hostname of the master machine.

	--interface | -i) <interface>			The interface to access the cluster.

	--vfs | -v) <vfs number>			The number of vfs to create on the interface.

	--master-ip) <master-ip>			The ip of the master node.

	--host-ip) <host-ip>				The ip of the host.

        --netmask) <the netmask to use>			The netmask of the network to access the cluster.

	--no-deps)					Do not install the dependencies, use this only if you have ran the 
							command before

	--svc-cidr)					The service ip to use for the cluster

	--net-cidr)					The pod network cidr to use for the cluster

	--go-version)					The go version to install.

	--topology-manager) <topology manager policy>	A flag to configure the kubelet topology manager policy.

	--is-bond)					Whether interface is a bond interface or not.

	--slave1) <slave interface 1>			In case of a bond interface the first slave of the bond interface.

	--slave2) <slave interface 2>			In case of a bond interface the second slave of the bond interface.

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

if [[ -z "$master_ip" ]]
then
   echo "The master IP address was not provided, please \
provide one using the --master-ip option"
   echo "Exiting...."
   exit 1
fi

if [[ -z $master_hostname ]]
then
   echo "The master hostname was not provided, please \
provide one using the --master-hostname option."
   echo "Exiting...."
   exit 1
fi

if [[ "$is_master" == "false" ]]
then 
   if [[ -z $ca_hash ]]
   then 
      echo "a token to join the cluster was provided \
            but no ca_cert hash was provided, please provide\
            one, EXITTING ....."
      exit 1
   fi
fi

if [[ ! -f utils/"$switchdev_scripts_name" ]]
then
   echo "utils/$switchdev_scripts_name: no such file
   please run the script from inside the dir containing the
   automation scripts or be sure it exists there!!"
   exit 1
fi

if [[ "$is_bond" == "true" ]]
then
   if [[ -z "$slave1" ]]
   then
      echo "The interface was configured to be a bond, but slave1 was not provided. Please provide one using the --slave1 option or slave1 option in the local.conf file."
      echo "Exiting...."
      exit 1
   fi

   if [[ -z "$slave2" ]]
   then
      echo "The interface was configured to be a bond, but slave2 was not provided. Please provide one using the --slave2 option or slave2 option in the local.conf file."
      echo "Exiting...."
      exit 1
   fi
fi


##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


system_args_check(){
   change_value "/etc/sysctl.conf" "net.ipv4.ip_forward" "1"
   change_value "/etc/sysctl.conf" "net.bridge.bridge-nf-call-iptables" "1"
   sysctl -p

   if [[ -n `swapon -s` ]]
   then
      swapoff -a
   fi

   swap_line_numbers="`grep -x -n "[^#]*swap.*" /etc/fstab | cut -d":" -f 1`"
   if [[ -n $swap_line_numbers ]]
   then
      for line_number in $swap_line_numbers;
      do
         sed -i "$line_number s/^/\#/g" /etc/fstab
      done
   fi

   if [[ `systemctl is-active firewalld` != "inactive" ]]
   then
      systemctl stop firewalld
   fi

   if [[ `systemctl is-enabled firewalld` != "disabled" ]]
   then
      systemctl disable firewalld
   fi
}

k8s_repo_setup(){
   if [[ ! -f "/etc/yum.repos.d/kubernetes.repo" ]] || [[ -z `\
   grep 'gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg' /etc/yum.repos.d/kubernetes.repo` ]]
   then
   sudo tee -a /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernets-stable]
name=Kuberenets
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
  fi
}

k8s_confs(){
   if [[ "$KUBECONFIG" != "/etc/kubernetes/admin.conf" ]]
   then
      export KUBECONFIG=/etc/kubernetes/admin.conf
   fi
   change_value "$HOME/.bashrc" "export KUBECONFIG" "/etc/kubernetes/admin.conf"
}

gopath_check(){
   if [[ "$GOPATH" != "$go_path" ]]
   then
      export GOPATH="/root/go"
   fi
   if [[ ! "$PATH" =~ :"$go_path/bin":? ]]
   then
      export PATH=$PATH:"$go_path"/bin
   fi
   change_value "$HOME/.bashrc" "export GOPATH" "/root/go"
   change_value "$HOME/.bashrc" "export PATH" "\$PATH:$go_path/bin"
}

hostname_add(){
   local_ip=$1
   local_hostname=$2
   if [[ -n "`grep "$local_ip" /etc/hosts`" ]]
   then
      sed -i "/$local_ip/d" /etc/hosts
   fi
   echo "$local_ip $local_hostname" >> /etc/hosts
}

golang_install(){
   logger "installing go"
   if [[ -z "$go_version" ]]
   then
      echo "no go version provided. please provide one using \
--go-version option"
      echo "Exiting...."
      exit 1
   fi
   go_tar=go"$go_version".linux-amd64.tar.gz
   yum install wget  git -y
   if [[ ! "`go version`" =~ "$go_version" ]]
   then
      if [[ ! -f $go_tar ]]
      then
         if [[ ! `wget -S --spider https://dl.google.com/go/"$go_tar"  2>&1 | grep 'HTTP/1.1 200 OK'` ]]
         then
            echo "no go version $go_version upstream!"
            echo "Exiting...."
            exit 1
         fi
         wget https://dl.google.com/go/$go_tar
      fi
      rm -rf /usr/local/go
      tar -C /usr/local -xzf $go_tar
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
      pushd $GOPATH/src/github.com/intel/sriov-cni
      make build
      popd
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
   k8s_repo_setup
   yum -y install kubelet apt-transport-https ca-certificates curl software-properties-common \
   python3-pip virtualenv python3-setuptools kubeadm
   
   if [[ "`systemctl is-enabled kubelet`" != "enabled" ]]
   then
      systemctl enable kubelet
   fi

   if [[ "`systemctl is-active kubelet`" != "active" ]]
   then
      systemctl start kubelet
   fi
 
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

create_vfs(){
   local_interface=$1
   local_vfs=$2
   switchdev_path=`pwd`/utils

   echo "$switchdev_path/$switchdev_scripts_name -i $local_interface -v $local_vfs" >> /etc/rc.d/rc.local
   bash "$switchdev_path"/"$switchdev_scripts_name" -i "$local_interface" -v "$local_vfs"

   chmod +x $switchdev_path/$switchdev_scripts_name
   chmod +x /etc/rc.d/rc.local
}

clean_rclocal(){
   if [[ -n $(grep "$switchdev_scripts_name" /etc/rc.d/rc.local) ]]
   then
      sed -i "/$switchdev_scripts_name/d" /etc/rc.d/rc.local
   fi
}

init_kubadmin(){
   if [[ `systemctl is-enabled openvswitch` == "disabled" ]]
   then
      systemctl enable openvswitch
   fi

   if [[ `systemctl is-active openvswitch` == "inactive" ]]
   then
      systemctl start openvswitch
      sleep 1

      if [[ `systemctl is-active openvswitch` == "inactive" ]]
      then
         exit 1
      fi
   fi

   

   if [[ "$is_master" == "true" ]]
   then 
   	kubeadm init --apiserver-advertise-address=$master_ip --node-name=$master_hostname  --skip-phases addon/kube-proxy --pod-network-cidr $net_cidr --service-cidr $svc_cidr
      export KUBECONFIG=/etc/kubernetes/admin.conf
      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config
      k8s_confs
      error_check "kubectl cluster-info" "The cluster was not created"
   else
      kubeadm join "$master_ip:6443" --token $token --discovery-token-ca-cert-hash $ca_hash
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
   sed -i "/^$wanted_variable/d" $file
   echo "$wanted_variable=$wanted_value" >> $file
}


##################################################
##################################################
###################   Main   #####################
##################################################
##################################################


system_args_check

gopath_check

hostname_add $host_ip $hostname
hostname_add $master_ip $master_hostname
if [[ $install_deps == "true" ]]
then
   golang_install
   cnis_install
   kubernetes_install
   docker_install
fi

clean_rclocal

if [[ "$is_bond" == "false" ]]
then
   ./utils/interface_prepare.sh --interface "$interface" --ip "$host_ip" --netmask "$netmask"
   create_vfs "$interface" "$vfs_num"
elif [[ "$is_bond" == "true" ]]
then
   ./utils/interface_prepare.sh --interface "$slave1" --bond slave --bond-master "$interface" --no-restart
   create_vfs "$slave1" "$vfs_num"
   ./utils/interface_prepare.sh --interface "$slave2" --bond slave --bond-master "$interface" --no-restart
   create_vfs "$slave2" "$vfs_num"
   ./utils/interface_prepare.sh --interface "$interface" --ip "$host_ip" --netmask "$netmask" --bond master
fi

init_kubadmin

if [[ -n "$topology_manager" ]]
then
   utils/topology_manager_setup.sh --policy "$topology_manager" --cpus auto --interface $interface
fi

if [[ "$is_master" == "true" ]]
then
   kubeadm token create --print-join-command   
fi
