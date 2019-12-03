#!/bin/bash
# This scripts create vfs on the interface and switch them to switchdev mode
# it accepts two parameters, the first is the name of the interface and the
# second is the number of vfs

set -ex
set -o pipefail
exec 1> >(logger -s -t $(basename $1)) 2>&1


##################################################
##################################################
####################   MAIN   ####################
##################################################
##################################################


# Configuring num of vfs for the interface
vendor_id="$(cat /sys/class/net/$1/device/vendor)"
if [ "$(cat /sys/class/net/$1/device/sriov_numvfs)" != "0" ]
then
  echo 0 >/sys/class/net/$1/device/sriov_numvfs
  sleep 2
fi
echo $2 >/sys/class/net/$1/device/sriov_numvfs

# Unbinding the vfs for mellanox interfaces
if [ $vendor_id == "0x15b3" ]
then
  vfs_pci_list=$(grep PCI_SLOT_NAME /sys/class/net/$1/device/virtfn*/uevent | cut -d'=' -f2)
  for pci in $vfs_pci_list
  do
    echo "$pci" > /sys/bus/pci/drivers/mlx5_core/unbind
  done
fi

# Moving the interface to switchdev mode
interface_pci=$(grep PCI_SLOT_NAME /sys/class/net/$1/device/uevent | cut -d'=' -f2)
/usr/sbin/devlink dev eswitch set pci/"$interface_pci" mode switchdev

# Binding the vfs for mellanox interfaces
if [ $vendor_id == "0x15b3" ]
then
  for pci in $vfs_pci_list
  do
    echo "$pci" > /sys/bus/pci/drivers/mlx5_core/bind
  done
fi


# ifup the interface

/usr/sbin/ifup $1
if [[ "$(/usr/sbin/devlink dev eswitch show pci/"$interface_pci")" =~ "mode switchdev" ]]
then
  echo "PCI device $interface_pci set to mode switchdev."
else
  echo "Failed to set PCI device $interface_pci to mode switchdev."
  exit 1
fi
interface_device=$(cat /sys/class/net/$1/device/device)
if [ "$interface_device" == "0x1013" ] || [ "$interface_device" == "0x1015" ]
then
  /usr/sbin/devlink dev eswitch set pci/"$interface_pci" inline-mode transport
fi

# Enabling hw-tc-offload for the interface
/usr/sbin/ethtool -K $1 hw-tc-offload on

# Enabling  hw-offload in ovs
#if [[ ! $(ovs-vsctl get Open_Vswitch . other_config:hw-offload | grep -i true) ]]
#then
#  ovs-vsctl set Open_Vswitch  . other_config:hw-offload=true
#fi

