# coreos-kubernetes-multi-node-generic-install-script
CoreOS Kubernetes multi-node generic install script modifications

I started this project to add support for etcd2 tls certificates for the controller worker script

so for now I have the following patches for controller and worker install scripts:

patch_update_engine_mask_flag.patch - by default the script masks the update engine, for people that still want their coreos auto updated, can disable this feature.

patch_overwrite_all_files_flag.patch - by default the script doesn't overwrrite configuration files for files that exists in the system, this creates a flag that overrides that

patch_etcd_tls_support.patch - this adds tls support for etcd2


