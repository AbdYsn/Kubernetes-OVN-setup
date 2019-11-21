set -ex


##################################################
##################################################
##################   input   #####################
##################################################
##################################################

while test $# -gt 0; do
  case "$1" in

   --help | -h)
      echo "
cleanup_script [options] A script tp cleanup the host from kubernetes 

options:
 
   --help | -h) <interface>		   show the help
"
      exit 0
      ;;
   
   *)
      echo "No such option, please see the help!!"
      echo "Exitting ...."
      exit 1
  esac
done

##################################################
##################################################
###################   Main   #####################
##################################################
##################################################

kubeadm reset -f 
rm -rf $HOME/.kube/config
rm -rf /var/log/openvswitch/
rm -rf /var/run/openvswitch/
rm -rf /var/log/ovn-kubernetes
#rm -rf /etc/openvswitch/