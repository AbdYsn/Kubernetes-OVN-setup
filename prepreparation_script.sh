#!/bin/bash

set -e
set -x

interface=""
hostname=""
hostip=""
reload="false"
hostname_change_flag="false"
default_interface="enp30f0"
pci_address=""

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

   --set-hostname)
      hostname_change_flag="true"
      shift
      ;;

   --default-interface)
      default_interface=$2
      shift
      shift
      ;;

   --pci-address)
      pci_address=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
setup_offload [options]: set up a kubernetes kubeadm environment with offloading enabled on the host machine.

options:
 
--interface | -i) <interface>		Specify the interface to enable the offloading on.
   
   --hostname) <cluster hostname>	The hostname to use for the cluster creating

   --set-hostname)

   --ip) <ip of cluster admin>		The ip of the admin host (master)

   --default-interface)

   --pci-address)

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

if [[ -z $pci_address ]]
then
   echo "The pci address of the interface was not provided !!!"
   echo "Please provide one using the option --pci-address"
   echo "for more informaton see the help menu --help or -h"
   echo "Exitting ...."
   exit 1
fi

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


hostname_check(){
   if [[ -z $hostip ]]
   then
      exit 1
   else
      if [[ $hostname_change_flag ]]
      then
      if [[ "`hostname`" != $hostname ]]
         then
            old_hostname=`hostname`
            hostname_line="`cat /etc/hosts | grep $old_hostname`"
            if [[ -n $hostname_line ]]
            then
               sed -i s/$hostname_line/"\#$hostname_line"/g /etc/hosts
            fi
            hostnamectl set-hostname $hostname
         fi
      fi

      if [[ -z "`cat /etc/hosts | grep $hostname | grep $hostip`" ]]
      then
         echo "$hostip $hostname" >> /etc/hosts
      fi 
   fi
}

gopath_check(){
if [[ -z `cat ~/.bashrc | grep GOPATH` ]] || [[ -z $GOPATH ]]
then
   cat >> ~/.bashrc <<EOF
export GOPATH=/root/go                                                                                                             
EOF
export GOPATH=/root/go
fi

if [[ -z `cat ~/.bashrc | grep "/usr/local/go/bin"` ]] || [[ $PATH != .*/usr/local/go/bin.* ]]
then
   cat >> ~/.bashrc <<EOF
export PATH=$PATH:/usr/local/go/bin
EOF
export PATH=$PATH:/usr/local/go/bin
fi

if [[ -z `cat ~/.bashrc | grep KUBECONFIG` ]] || [[ -z $KUBECONFIG ]]
then
   cat >> ~/.bashrc <<EOF
export KUBECONFIG=/etc/kubernetes/admin.conf                                                                                                      
EOF
export KUBECONFIG=/etc/kubernetes/admin.conf
fi
}

kubernetes_repo_check(){
   if [[ ! -f "/etc/yum.repos.d/kubernetes.repo" ]] || [[ -z `cat /etc/yum.repos.d/kubernetes.repo | grep \
   gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg` ]]
   then
   cat >> /etc/yum.repos.d/kubernetes.repo << EOF
[kubernets-stable]
name=Kuberenets
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF  
  fi
}

system_args_check(){
   if [[ -z `cat /etc/sysctl.conf | grep net.ipv4.ip_forward` ]]
   then
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
      sysctl -p
   elif [[ `cat /etc/sysctl.conf | grep net.ipv4.ip_forward | cut -d"=" -f 2` != "1" ]]
   then
      sed -i s/net.ipv4.ip_forward=./net.ipv4.ip_forward=1/g /etc/sysctl.conf
      sysctl -p
   fi
   
   if [[ -n `swapon -s` ]]
   then
      swapoff -a
   fi

   swap_line="`cat /etc/fstab | grep swap`"

   if [[ -n $swap_line ]]
   then
      sed -i s/$swap_line/"\#$swap_line"/g /etc/fstab
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

interface_name_check(){
   is_interface="false"
   interfaces_list=`ls /sys/class/net`
   for sys_interface in $interfaces_list;
   do
      if [[ $sys_interface == $default_interface ]]
      then
         is_interface="true"
         break
      fi
   done

   if [[ $is_interface == "false" ]]
   then
      for sys_interface in $interfaces_list;
      do
         if [[ $sys_interface != $interface ]]
         then
            change_interface_name
            break
         fi
      done
   fi
}

change_interface_name(){
   check_line="`cat /etc/udev/rules.d/70-persistent-ipoib.rules | grep $pci_address`"
   if [[ -z $check_line ]]
   then
      echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\" Kernel==\"$pci_address\", name==\"$default_interface\"" \
      >> /etc/udev/rules.d/70-persistent-ipoib.rules
   elif [[ $check_line == .*name==.* ]]
   then
      sed -i s/name==$default_interface//
   fi
}

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################

hostname_check
gopath_check
kubernetes_repo_check
system_args_check