#!/bin/bash

#set -e
set -x
exec 1> >(logger -s -t $(basename $0)) 2>&1

interface=""
hostname=""
master_hostname=""
host_ip=""
reload="false"
hostname_change_flag="false"
pci_address=""
vfs_num=""
master_ip=""
netmask="255.255.255.0"
switchdev_scripts_name="switchdev_setup.sh"

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

   --master-hostname)
      master_hostname=$2
      shift
      shift
      ;;

   --ip)
      master_ip=$2
      shift
      shift
      ;;

   --netmask)
      netmask=$2
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

   --vfs-num)
      vfs_num=$2
      shift
      shift
      ;;

   --help | -h)
      echo "
prepration_script [options] --ip <master ip> --master-hostname <master hostname> --hostname <hostname of host> --netmask <network netmask>\
 --vfs-num <number of vfs to create> --interface <the interface to create the vfs on>: prepare the host by initializing some global\
  variables and setting the hostname.

options:
 
   --interface | -i) <interface>		      the name to be used to rename the netdev at the specified pci address and configure
                                          the switchdev on.
   
   --hostname) <host hostname>	         The hostname of the current host

   --set-hostname) <new hostname>         aflag used if you want to change the hostname of the machine to the specified host name

   --master-hostname) <master hostname>   The hostname of the master

   --ip) <ip of the master node>		      The ip of the master node

   --netmask) <netmask>                   The cluster network netmask, used to configure the interface.

   --pci-address)                         The pci address of the net device to use, if present it is used to change the name of the net device

   --vfs-num)                             The number of vfs to create for switchdev mode

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

if [[ -z "$interface" ]]
then
   echo "The interface was not provided !!!
   Please provide one using the option --interface
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

if [[ -z $hostname ]]
then
   logger "The hostname was not provided !!!
   Will use the machine hostname
   you can provide one using the option --hostname"
   hostname=`hostname -f`
   logger "the hostname that will be used is: $hostname"
fi

if [[ -z $master_hostname ]]
then
   echo "The master hostname was not provided !!!
   Please provide one using the option --master-hostname
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

if [[ -z $master_ip ]]
then
   echo "The master ip was not provided !!!
   Please provide one using the option --ip
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

if [[ -z $netmask ]]
then
   echo "The netmask was not provided !!!
   Please provide one using the option --netmask
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

if [[ -z "$vfs_num" ]]
then
   echo "The number of vfs was not provided !!!
   Please provide one using the option --interface
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

my_path=`pwd`
if [[ ! -f $my_path/$switchdev_scripts_name ]]
then
   echo "$my_path/$switchdev_scripts_name: no such file
   please run the script from inside the dir containing the 
   automation scripts or be sure it exists there!!"
   exit 1
fi

host_ip=`ifconfig $interface | grep -o "inet [0-9.]* " | cut -d" " -f 2`
if [[ -z "$host_ip" ]]
then
   echo "no ip on the provided interface, please make sure that the network\
    settings are correct !!!
   Please provide one using the option --interface
   for more informaton see the help menu --help or -h
   Exitting ...."
   exit 1
fi

##################################################
##################################################
###############   Functions   ####################
##################################################
##################################################


hostname_check(){
   hostname_add $master_ip $master_hostname
   hostname_add $host_ip $hostname

   if [[ $hostname_change_flag == "true" ]]
   then
   if [[ "`hostname`" != $hostname ]]
      then
         old_hostname=`hostname`
         hostname_line="`cat /etc/hosts | grep $old_hostname`"
         if [[ -n $hostname_line ]]
         then
            sed -i "s/$old_hostname/$hostname/g" /etc/hosts
         fi
         hostnamectl set-hostname $hostname
      fi
   fi
}

hostname_add(){
   ip=$1
   local_hostname=$2
   if [[ -z "`cat /etc/hosts | grep $ip`" ]]
   then
      echo "$ip $local_hostname" >> /etc/hosts
   else
      if [[ "`cat /etc/hosts | grep $ip | cut -d\" \" -f 2`" != "$local_hostname" ]]
      then
         old_host="`cat /etc/hosts | grep $ip | cut -d" " -f 2`"
         sed -i "s/$old_host/$local_hostname/g" /etc/hosts
      fi
   fi
}

gopath_check(){
if [[ -z "`cat ~/.bashrc | grep GOPATH`" ]]
then
   sudo tee -a ~/.bashrc <<EOF
export GOPATH=/root/go                                                                                                             
EOF
export GOPATH=/root/go
fi

if [[ -z "`cat ~/.bashrc | grep "/usr/local/go/bin"`" ]]
then
   sudo tee -a ~/.bashrc <<EOF
export PATH=$PATH:/usr/local/go/bin
EOF
export PATH=$PATH:/usr/local/go/bin
fi

if [[ -z "`cat ~/.bashrc | grep KUBECONFIG`" ]]
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
   else
      change_content "/etc/sysctl.conf" "net.bridge.bridge-nf-call-iptables" "1"
      sysctl -p
   fi
   
   if [[ -z `cat /etc/sysctl.conf | grep net.bridge.bridge-nf-call-iptables` ]]
   then
      echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.conf
      sysctl -p
   else
      change_content "/etc/sysctl.conf" "net.bridge.bridge-nf-call-iptables" "1"
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

   if [[ -z `cat /etc/rc.local | grep $switchdev_scripts_name` ]]
   then
      echo "$my_path/$switchdev_scripts_name $interface $vfs_num" >> /etc/rc.local
   elif [[ `cat /etc/rc.local | grep $switchdev_scripts_name | cut -d" " -f 2` != "$interface" ]] ||\
    [[ `cat /etc/rc.local| grep $switchdev_scripts_name| cut -d" " -f 3` != "$vfs_num" ]]
   then
      sed -i "s/$switchdev_scripts_name [0-9a-zA-Z]* [0-9]*/$switchdev_scripts_name $interface $vfs_num/g" /etc/rc.local
   fi
   chmod +x $my_path/$switchdev_scripts_name
   chmod +x /etc/rc.local
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
      change_interface_name $pci_address $interface $old_interface_name
   fi
}

change_interface_name(){
   check_line=`cat /etc/udev/rules.d/70-persistent-ipoib.rules | grep $1 | sed 's/\"/\\\"/g' | sed 's/\*/\\\*/g'`
   if [[ -z $check_line ]]
   then
      echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\" KERNELS==\"$1\", NAME=\"$2\"" \
      >> /etc/udev/rules.d/70-persistent-ipoib.rules
   else
      new_line="ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\" KERNELS==\"$1\", NAME=\"$2\""
      sed -i "s/$check_line/$new_line/g" /etc/udev/rules.d/70-persistent-ipoib.rules
   fi

   change_content /etc/sysconfig/network-scripts/ifcfg-$3 "NAME" $2
   change_content /etc/sysconfig/network-scripts/ifcfg-$3 "DEVICE" $2
   mv /etc/sysconfig/network-scripts/ifcfg-$3 /etc/sysconfig/network-scripts/ifcfg-$2
   
}

interface_ip_config(){
   conf_file=/etc/sysconfig/network-scripts/ifcfg-$1

   if [[ -z `cat $conf_file | grep IPADDR` ]]
   then
      echo "IPADDR=$host_ip" >> $conf_file
   else
      change_content $conf_file IPADDR $host_ip
   fi   

   if [[ -z `cat $conf_file | grep NETMASK` ]]
   then
      echo "NETMASK=$netmask" >> $conf_file
   else
      change_content $conf_file NETMASK $netmask
   fi

}

change_content(){
   file=$1
   content=$2
   new_value=$3
   if [[ `cat $file | grep $content | cut -d"=" -f 2` != "$new_value" ]]
   then
      sed -i s/"$content=.*"/"$content=$new_value"/g $file
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
interface_ip_config $interface
./$switchdev_scripts_name $interface $vfs_num
if [[ `ls /sys/class/net/$interface/device/ | grep virtfn[0-9]* | wc -l` != $vfs_num ]]
then
   exit 1
fi
echo "Please reboot the host"
