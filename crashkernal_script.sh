#!/bin/bash

set -e

if [[ -z $1 ]]
then
crashkernel="512M"
else
crashkernel=$1
fi

dep_install(){
	if [[ -z  `rpm -qa | grep $1` ]]
	then
		yum install $1
		echo "installed $1"
	else
		echo "$1 is already installed"
	fi
}

set_crashkernel(){
	echo "setting crashkernal to $crashkernel"
	if [[ -n `cat /etc/default/grub | grep -o crashkernel=[0-9a-zA-Z]*" "` ]]
	then
        	sed -i -e s/crashkernel=[0-9a-zA-Z]*" "/"crashkernel=$crashkernel "/ /etc/default/grub
	else
        	sed -i -e s/"GRUB_CMDLINE_LINUX=\""/"GRUB_CMDLINE_LINUX=\"crashkernel=$crashkernel "/ /etc/default/grub
	fi
}

dep_install kexec-tools
set_crashkernel 
grub2-mkconfig -o /boot/grub2/grub.cfg

