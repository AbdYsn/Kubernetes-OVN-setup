#!/bin/bash

set -e
set -x

interface=""
hostname=""
hostip=""
reload="false"
hostname_change_flag="false"
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

   --pci-address)
      pci_address=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
prepration_script [options] --ip <master ip> --hostname <master hostname>: prepare the host by initializing some global variables\
and setting the hostname.

options:
 
   --interface | -i) <interface>		   the name to be used to rename the netdev at the specified pci address.
   
   --hostname) <cluster hostname>	The hostname of the master node

   --set-hostname)                  aflag used to if you want to change the hostname of the machine to the specified host name

   --ip) <ip of cluster admin>		The ip of the master node

   --pci-address)                   The pci address of the net device to use, it is used to change the name of the net device

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

if [[ -n $pci_address ]]
then
   if [[ -z $interface ]]
   then
      echo "No interface was provided !!!"
      echo "Please provide one using the option --interface or -i"
      echo "for more informaton see the help menu --help or -h"
      echo "Exitting ...."
      exit 1
   fi
fi


if [[ -z $hostname ]]
then
   echo "The hostname was not provided !!!"
   echo "Will use the machine hostname"
   echo "you can provide one using the option --hostname"
   hostname=`hostname -f`
   echo "the hostname that will be used is: $hostname"
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
      if [[ $hostname_change_flag == "true" ]]
      then
      if [[ "`hostname`" != $hostname ]]
         then
            old_hostname=`hostname`
            hostname_line="`cat /etc/hosts | grep $old_hostname`"
            if [[ -n $hostname_line ]]
            then
               sed -i "s/$hostname_line/"\#$hostname_line"/g" /etc/hosts
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
if [[ -z `cat ~/.bashrc | grep GOPATH` ]]
then
   sudo tee -a ~/.bashrc <<EOF
export GOPATH=/root/go                                                                                                             
EOF
export GOPATH=/root/go
fi

if [[ -z `cat ~/.bashrc | grep "/usr/local/go/bin"` ]]
then
   sudo tee -a ~/.bashrc <<EOF
export PATH=$PATH:/usr/local/go/bin
EOF
export PATH=$PATH:/usr/local/go/bin
fi

if [[ -z `cat ~/.bashrc | grep KUBECONFIG` ]
then
   sudo tee -a ~/.bashrc <<EOF
export KUBECONFIG=/etc/kubernetes/admin.conf                                                                                                      
EOF
export KUBECONFIG=/etc/kubernetes/admin.conf
fi
}

kubernetes_repo_check(){
   if [[ ! -f "/etc/yum.repos.d/kubernetes.repo" ]] || [[ -z `cat /etc/yum.repos.d/kubernetes.repo | grep \
   gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg` ]]
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
      sed -i "s/.*swap.*/\#$swap_line/g" /etc/fstab
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
   
   if [[ -z $pci_address ]]
   then
      return
   fi

   old_interface_name=`ls /sys/bus/pci/devices/$pci_address/net/`
   if [[ $old_interface_name != $interface ]]
   then 
      interfaces_list=`ls /sys/class/net`
      for sys_interface in $interfaces_list;
      do
         if [[ $sys_interface == $interface ]]
         then
         # in this case there is an interface with the name specified, but it does not
         # have the same pci address, the user should choose another name.
            exit 1
         fi
      done
      change_interface_name $pci_address $interface
   fi

}

change_interface_name(){
   check_line=`cat /etc/udev/rules.d/70-persistent-ipoib.rules | grep $1 | sed 's/\"/\\\"/g' | sed 's/\*/\\\*/g'`
   if [[ -z $check_line ]]
   then
      echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\" Kernel==\"$1\", name==\"$2\"" \
      >> /etc/udev/rules.d/70-persistent-ipoib.rules
   else
      new_line="ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\" Kernel==\"$1\", name==\"$2\""
      sed -i "s/$check_line/$new_line/g" /etc/udev/rules.d/70-persistent-ipoib.rules
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
interface_name_check
echo "Please source the file ~/.bashrc"