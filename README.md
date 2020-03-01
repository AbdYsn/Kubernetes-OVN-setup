Kubernetes OVN setup scripts
============================

This repository contains scripts to automatically deploy the kubenetes with OVN and
SRIOV device plugin.

How to use:
-----------

 * Configure the `local.conf` file as needed.

 * Run the `preparation_script.sh` script on all nodes.

 * Run the `setup_kubernetes.sh` script on the master node and copy the `token` and `ca_hash`.

 * Edit the `local.conf` file in the worker nodes and set the `token` and `ca_hash`.

 * Run the `setup_kubernetes.sh` on the worker nodes.

 * Run the `ovnkube_deploy.sh` script on all nodes.

 * Run the `daemonset_deploy.sh` script on the master node
