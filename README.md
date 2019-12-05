# BashScripts
usage steps: 
    1- configure the local.conf file.
    2- run the preparation_script.sh script on all nodes.
    3- run the setup_kubernetes.sh script on the master node and copy the token and ca_hash.
    4- edit the local.conf file in the worker nodes and set the token and ca_hash
    5- run the setup_kubernetes.sh on the worker nodes
    6- run the ovnkube_deploy.sh script on all nodes.
    7- run the daemonset_deploy.sh script on the master node
