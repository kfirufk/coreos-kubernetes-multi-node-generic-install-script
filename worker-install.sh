#!/bin/bash
set -e

# List of etcd servers (http://ip:port), comma separated
export ETCD_ENDPOINTS=

# The endpoint the worker node should use to contact controller nodes (https://ip:port)
# In HA configurations this should be an external DNS record or loadbalancer in front of the control nodes.
# However, it is also possible to point directly to a single control node.
export CONTROLLER_ENDPOINT=

# Specify the version (vX.Y.Z) of Kubernetes assets to deploy
export K8S_VER=v1.4.1_coreos.0

# Hyperkube image repository to use.
export HYPERKUBE_IMAGE_REPO=quay.io/coreos/hyperkube

# The IP address of the cluster DNS service.
# This must be the same DNS_SERVICE_IP used when configuring the controller nodes.
export DNS_SERVICE_IP=10.3.0.10

# Whether to use Calico for Kubernetes network policy.
export USE_CALICO=false

# Determines the container runtime for kubernetes to use. Accepts 'docker' or 'rkt'.
export CONTAINER_RUNTIME=docker

# to re-create all existing configuration files ?
export OVERWRITE_ALL_FILES=false

export ETCD_AUTHORITY=localhost:2379
# etcd scheme
export ETCD_SCHEME="https"

# etcd certificates root directory
export ETCD_CERT_ROOT_DIR="/etc/ssl/etcd"

# Should etcd tls certificates should be enabled to connect to etcd servers
export ETCD_CLIENT_CERT_AUTH=true
# etcd certificate file
export ETCD_CERT_FILE="/etc/ssl/etcd/etcd2.pem"
# etcd key file
export ETCD_KEY_FILE="/etc/ssl/etcd/etcd2-key.pem"
# etcd CA certificate
export ETCD_TRUSTED_CA_FILE="/etc/ssl/etcd/ca.pem"

# to mask update-engine ?
export IS_MASK_UPDATE_ENGINE=true

# The above settings can optionally be overridden using an environment file:
ENV_FILE=/run/coreos-kubernetes/options.env

# -------------

function init_config {
    local REQUIRED=( 'ADVERTISE_IP' 'ETCD_ENDPOINTS' 'CONTROLLER_ENDPOINT' 'DNS_SERVICE_IP' 'K8S_VER' 'HYPERKUBE_IMAGE_REPO' 'USE_CALICO' )

    if [ -f $ENV_FILE ]; then
        export $(cat $ENV_FILE | xargs)
    fi
    if [ -z $ADVERTISE_IP ]; then
        export ADVERTISE_IP=$(awk -F= '/COREOS_PUBLIC_IPV4/ {print $2}' /etc/environment)
    fi

    for REQ in "${REQUIRED[@]}"; do
        if [ -z "$(eval echo \$$REQ)" ]; then
            echo "Missing required config value: ${REQ}"
            exit 1
        fi
    done
}

function init_templates {
    local TEMPLATE=/etc/systemd/system/kubelet.service
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
[Service]
Environment=KUBELET_VERSION=${K8S_VER}
Environment=KUBELET_ACI=${HYPERKUBE_IMAGE_REPO}
Environment="RKT_OPTS=--volume dns,kind=host,source=/etc/resolv.conf \
  --mount volume=dns,target=/etc/resolv.conf \
  --volume rkt,kind=host,source=/opt/bin/host-rkt \
  --mount volume=rkt,target=/usr/bin/rkt \
  --volume var-lib-rkt,kind=host,source=/var/lib/rkt \
  --mount volume=var-lib-rkt,target=/var/lib/rkt \
  --volume stage,kind=host,source=/tmp \
  --mount volume=stage,target=/tmp \
  --volume var-log,kind=host,source=/var/log \
  --mount volume=var-log,target=/var/log"
ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
ExecStartPre=/usr/bin/mkdir -p /var/log/containers
ExecStart=/usr/lib/coreos/kubelet-wrapper \
  --api-servers=${CONTROLLER_ENDPOINT} \
  --cni-conf-dir=/etc/kubernetes/cni/net.d \
  --network-plugin=cni \
  --container-runtime=${CONTAINER_RUNTIME} \
  --rkt-path=/usr/bin/rkt \
  --rkt-stage1-image=coreos.com/rkt/stage1-coreos \
  --register-node=true \
  --allow-privileged=true \
  --config=/etc/kubernetes/manifests \
  --hostname-override=${ADVERTISE_IP} \
  --cluster_dns=${DNS_SERVICE_IP} \
  --cluster_domain=cluster.local \
  --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml \
  --tls-cert-file=/etc/kubernetes/ssl/worker.pem \
  --tls-private-key-file=/etc/kubernetes/ssl/worker-key.pem
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    fi

    local TEMPLATE=/opt/bin/host-rkt
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
#!/bin/sh
# This is bind mounted into the kubelet rootfs and all rkt shell-outs go
# through this rkt wrapper. It essentially enters the host mount namespace
# (which it is already in) only for the purpose of breaking out of the chroot
# before calling rkt. It makes things like rkt gc work and avoids bind mounting
# in certain rkt filesystem dependancies into the kubelet rootfs. This can
# eventually be obviated when the write-api stuff gets upstream and rkt gc is
# through the api-server. Related issue:
# https://github.com/coreos/rkt/issues/2878
exec nsenter -m -u -i -n -p -t 1 -- /usr/bin/rkt "\$@"
EOF
    fi

    local TEMPLATE=/etc/systemd/system/load-rkt-stage1.service
    if [ ${CONTAINER_RUNTIME} = "rkt" ] && [ ! -f $TEMPLATE ] || [ ${CONTAINER_RUNTIME} = "rkt" ] && [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
[Unit]
Description=Load rkt stage1 images
Documentation=http://github.com/coreos/rkt
Requires=network-online.target
After=network-online.target
Before=rkt-api.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/rkt fetch /usr/lib/rkt/stage1-images/stage1-coreos.aci /usr/lib/rkt/stage1-images/stage1-fly.aci  --insecure-options=image

[Install]
RequiredBy=rkt-api.service
EOF
    fi

    local TEMPLATE=/etc/systemd/system/rkt-api.service
    if [ ${CONTAINER_RUNTIME} = "rkt" ] && [ ! -f $TEMPLATE ] || [ ${CONTAINER_RUNTIME} = "rkt" ] && [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
[Unit]
Before=kubelet.service

[Service]
ExecStart=/usr/bin/rkt api-service
Restart=always
RestartSec=10

[Install]
RequiredBy=kubelet.service
EOF
    fi

    local TEMPLATE=/etc/systemd/system/calico-node.service
    if [ "${USE_CALICO}" = "true" ] && [ ! -f "${TEMPLATE}" ] || [ "${USE_CALICO}" = "true" ] && [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
[Unit]
Description=Calico per-host agent
Requires=network-online.target
After=network-online.target

[Service]
Slice=machine.slice
Environment=CALICO_DISABLE_FILE_LOGGING=true
Environment=HOSTNAME=${ADVERTISE_IP}
Environment=IP=${ADVERTISE_IP}
Environment=FELIX_FELIXHOSTNAME=${ADVERTISE_IP}
Environment=CALICO_NETWORKING=true
Environment=NO_DEFAULT_POOLS=true
Environment=ETCD_ENDPOINTS=${ETCD_ENDPOINTS}

ExecStart=/usr/bin/rkt run --inherit-env --stage1-from-dir=stage1-fly.aci \
--volume=var-run-calico,kind=host,source=/var/run/calico \
--volume=modules,kind=host,source=/lib/modules,readOnly=false \
--mount=volume=modules,target=/lib/modules \
--volume=dns,kind=host,source=/etc/resolv.conf,readOnly=true \
--mount=volume=dns,target=/etc/resolv.conf \
--mount=volume=var-run-calico,target=/var/run/calico \
--trust-keys-from-https quay.io/calico/node:v0.22.0
KillMode=mixed
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
        if [ "$ETCD_CLIENT_CERT_AUTH" = true ]; then
       sed -i "15i Environment=ETCD_AUTHORITY=$ETCD_AUTHORITY" $TEMPLATE
       sed -i "16i Environment=ETCD_SCHEME=$ETCD_SCHEME" $TEMPLATE
       sed -i "17i Environment=ETCD_CA_CERT_FILE=$ETCD_TRUSTED_CA_FILE" $TEMPLATE
       sed -i "18i Environment=ETCD_CERT_FILE=$ETCD_CERT_FILE" $TEMPLATE
       sed -i "19i Environment=ETCD_KEY_FILE=$ETCD_KEY_FILE" $TEMPLATE
       sed -i -e "21s#.*#ExecStart=/usr/bin/rkt run --inherit-env --stage1-from-dir=stage1-fly.aci --volume=modules,kind=host,source=/lib/modules,readOnly=false --mount=volume=modules,target=/lib/modules --volume=dns,kind=host,source=/etc/resolv.conf,readOnly=true --volume=etcd-tls-certs,kind=host,source=$ETCD_CERT_ROOT_DIR,readOnly=true --mount=volume=dns,target=/etc/resolv.conf --mount=volume=etcd-tls-certs,target=/etc/ssl/etcd --trust-keys-from-https quay.io/calico/node:v0.22.0#g" $TEMPLATE
       fi
    fi

    local TEMPLATE=/etc/kubernetes/worker-kubeconfig.yaml
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    certificate-authority: /etc/kubernetes/ssl/ca.pem
users:
- name: kubelet
  user:
    client-certificate: /etc/kubernetes/ssl/worker.pem
    client-key: /etc/kubernetes/ssl/worker-key.pem
contexts:
- context:
    cluster: local
    user: kubelet
  name: kubelet-context
current-context: kubelet-context
EOF
    fi

    local TEMPLATE=/etc/kubernetes/manifests/kube-proxy.yaml
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
apiVersion: v1
kind: Pod
metadata:
  name: kube-proxy
  namespace: kube-system
  annotations:
    rkt.alpha.kubernetes.io/stage1-name-override: coreos.com/rkt/stage1-fly
spec:
  hostNetwork: true
  containers:
  - name: kube-proxy
    image: ${HYPERKUBE_IMAGE_REPO}:$K8S_VER
    command:
    - /hyperkube
    - proxy
    - --master=${CONTROLLER_ENDPOINT}
    - --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml
    securityContext:
      privileged: true
    volumeMounts:
    - mountPath: /etc/ssl/certs
      name: "ssl-certs"
    - mountPath: /etc/kubernetes/worker-kubeconfig.yaml
      name: "kubeconfig"
      readOnly: true
    - mountPath: /etc/kubernetes/ssl
      name: "etc-kube-ssl"
      readOnly: true
    - mountPath: /var/run/dbus
      name: dbus
      readOnly: false
  volumes:
  - name: "ssl-certs"
    hostPath:
      path: "/usr/share/ca-certificates"
  - name: "kubeconfig"
    hostPath:
      path: "/etc/kubernetes/worker-kubeconfig.yaml"
  - name: "etc-kube-ssl"
    hostPath:
      path: "/etc/kubernetes/ssl"
  - hostPath:
      path: /var/run/dbus
    name: dbus
EOF
    fi

    local TEMPLATE=/etc/flannel/options.env
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
FLANNELD_IFACE=$ADVERTISE_IP
FLANNELD_ETCD_ENDPOINTS=$ETCD_ENDPOINTS
EOF
    if [ "$ETCD_CLIENT_CERT_AUTH" = true ]; then
    printf "FLANNELD_ETCD_CAFILE=$ETCD_TRUSTED_CA_FILE\nFLANNELD_ETCD_CERTFILE=$ETCD_CERT_FILE\nFLANNELD_ETCD_KEYFILE=$ETCD_KEY_FILE\n" >> $TEMPLATE
    fi
    fi

    local TEMPLATE=/etc/systemd/system/flanneld.service.d/40-ExecStartPre-symlink.conf.conf
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
[Service]
ExecStartPre=/usr/bin/ln -sf /etc/flannel/options.env /run/flannel/options.env
EOF
    fi

    local TEMPLATE=/etc/systemd/system/docker.service.d/40-flannel.conf
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
[Unit]
Requires=flanneld.service
After=flanneld.service
[Service]
EnvironmentFile=/etc/kubernetes/cni/docker_opts_cni.env
EOF
    fi

    local TEMPLATE=/etc/kubernetes/cni/docker_opts_cni.env
    if [ ! -f $TEMPLATE ] || [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
DOCKER_OPT_BIP=""
DOCKER_OPT_IPMASQ=""
EOF
    fi

    local TEMPLATE=/etc/kubernetes/cni/net.d/10-calico.conf
    if [ "${USE_CALICO}" = "true" ] && [ ! -f "${TEMPLATE}" ] || [ "${USE_CALICO}" = "true" ] && [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
{
    "name": "calico",
    "type": "flannel",
    "delegate": {
        "type": "calico",
        "etcd_endpoints": "$ETCD_ENDPOINTS",
        "log_level": "debug",
        "log_level_stderr": "info",
        "hostname": "${ADVERTISE_IP}",
        "policy": {
            "type": "k8s",
            "k8s_api_root": "${CONTROLLER_ENDPOINT}:443/api/v1/",
            "k8s_client_key": "/etc/kubernetes/ssl/worker-key.pem",
            "k8s_client_certificate": "/etc/kubernetes/ssl/worker.pem"
        }
    }
}
EOF
	if [ "$ETCD_CLIENT_CERT_AUTH" = true ]; then
       sed -i "7i 	\"etcd_key_file\": \"$ETCD_KEY_FILE\"," $TEMPLATE
       sed -i "8i 	\"etcd_cert_file\": \"$ETCD_CERT_FILE\"," $TEMPLATE
       sed -i "9i 	\"etcd_ca_cert_file\": \"$ETCD_TRUSTED_CA_FILE\"," $TEMPLATE
	fi
    fi

    local TEMPLATE=/etc/kubernetes/cni/net.d/10-flannel.conf
    if [ "${USE_CALICO}" = "false" ] && [ ! -f "${TEMPLATE}" ] || [ "${USE_CALICO}" = "false" ] && [ "$OVERWRITE_ALL_FILES" = true ]; then
        echo "TEMPLATE: $TEMPLATE"
        mkdir -p $(dirname $TEMPLATE)
        cat << EOF > $TEMPLATE
{
    "name": "podnet",
    "type": "flannel",
    "delegate": {
        "isDefaultGateway": true
    }
}
EOF
    fi

}

init_config
init_templates

chmod +x /opt/bin/host-rkt

if [ "$IS_MASK_UPDATE_ENGINE" = true ]; then
	systemctl stop update-engine; systemctl mask update-engine
fi

systemctl daemon-reload
if [ $CONTAINER_RUNTIME = "rkt" ]; then
        systemctl enable load-rkt-stage1
        systemctl enable rkt-api
fi
systemctl enable flanneld; systemctl start flanneld
systemctl enable kubelet; systemctl start kubelet
if [ $USE_CALICO = "true" ]; then
        systemctl enable calico-node; systemctl start calico-node
fi
