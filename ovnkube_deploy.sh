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
interface=parse_conf interface
gateway=parse_conf gateway
docker_image=parse_conf docker_image
net_cidr=parse_conf net_cidr
svc_cidr=parse_conf svc_cidr

master="false"

##################################################
##################################################
##################   input   #####################
##################################################
##################################################

while test $# -gt 0; do
  case "$1" in
   
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
      gateway=$2
      shift
      shift
      ;;
    
    --master)
      master="true"
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

   --help | -h)
      echo "
ovnkube_deploy.sh [options]: set up the ovn cni and deploy the deployments and daemonsets.

options:
	--ip) <ip of cluster admin>			The ip of the master host

	--interface)					The interface to the cluster

	--gateway)					The gateway of the network

	--docker-image)					The image to use to create the ovn containers

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



if [[ -z $hostip ]]
then
    echo "The ip address was not provided !!!
    Please provide one using the option --ip
    for more informaton see the help menu --help or -h
    Exitting ...."
    exit 1
fi

if [[ -n $master ]]
then
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
}

deploy_components(){
   if [[ -d $HOME/ovn-kubernetes/dist/yaml/ ]]
   then
      file_configuration
      cd $HOME/ovn-kubernetes/dist/yaml/
      kubectl create -f ovn-setup.yaml
      kubectl create -f ovnkube-db.yaml
      kubectl create -f ovnkube-master.yaml
      kubectl create -f ovnkube-node.yaml
   else 
      exit 1
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
      sed -i "$gateway_opt_value_line s/value: \"\"/value: \"--gateway-interface=$interface --gateway-nexthop=$gateway\"/"\
      /root/ovn-kubernetes/dist/yaml/ovnkube-node.yaml
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

check_dir(){
   dir=$1
   error_msg=$2
   if [[ ! -d $dir ]]
      then
         logger $error_msg
         exit 1
      fi
}

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################

ovn_cni_setup

if [[ "$master" == "true" ]]
then
    deploy_components
fi
