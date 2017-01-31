#deprecated

welp.. each etcd2 server has it's own certificates and I can't really tell each server to connect to a specific etcd2 server so I need to store the certificates of all the etcd2 certificates in the same directory. 

anyhow.. creating an etcd2 proxy at http://127.0.0.1:4001 solved the need for etcd2 certificaes.

# coreos-kubernetes-multi-node-generic-install-script
CoreOS Kubernetes multi-node generic install script modifications

I started this project to add support for etcd2 tls certificates for the controller worker script

so for now I have the following patches for controller and worker install scripts:

patch_update_engine_mask_flag.patch - by default the script masks the update engine, for people that still want their coreos auto updated, can disable this feature.

patch_overwrite_all_files_flag.patch - by default the script doesn't overwrrite configuration files for files that exists in the system, this creates a flag that overrides that

patch_etcd_tls_support.patch - this adds tls support for etcd2


