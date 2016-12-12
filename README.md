# coreos-kubernetes-multi-node-generic-install-script
CoreOS Kubernetes multi-node generic install script modifications

I started this project to add support for etcd2 tls certificates for the controller worker script

so for now I have the following patches for controller and worker install scripts:

INIT_01_patch_calico_node_version.patch - allows to modify calico node image version

patch_update_engine_mask_flag.patch - by default the script masks the update engine, for people that still want their coreos auto updated, can disable this feature.

patch_overwrite_all_files_flag.patch - by default the script doesn't overwrrite configuration files for files that exists in the system, this creates a flag that overrides that

patch_etcd_tls_support.patch - this adds tls support for etcd2


** before applying specific patches on the scripts, the INIT_* patches needs to be applied first.
