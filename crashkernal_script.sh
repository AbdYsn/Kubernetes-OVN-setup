#!/bin/bash

set -e

if [[ -z $1 ]]
then
crashkernel="512M"
else
crashkernel=$1
fi

kexec_install(){
	if [[ -z  `rpm -qa | grep "kexec-tools"` ]]
	then
		yum install kexec-tools &
		echo "installed kexec-tools"
	else
		echo "kexec-tools is already installed"
	fi
}

set_crashkernel(){
	echo "setting crashkernal to $crashkernel"
	if [[ -n `cat /etc/default/grub | grep -o crashkernel=[0-9a-zA-Z]*" "` ]]
	then
        	sed -i -e s/crashkernel=[0-9a-zA-Z]*" "/"crashkernel=$1 "/ /etc/default/grub
	else
        	sed -i -e s/"GRUB_CMDLINE_LINUX=\""/"GRUB_CMDLINE_LINUX=\"crashkernel=$1 "/ /etc/default/grub
	fi
}

kexec_install
set_crashkernel $crashkernel
grub2-mkconfig -o /boot/grub2/grub.cfg

