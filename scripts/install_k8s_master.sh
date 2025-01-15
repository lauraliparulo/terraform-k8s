#!/bin/bash

######### ** FOR MASTER NODE ** #########

hostname k8s-master-1
echo "k8s-master-1" > /etc/hostname

export AWS_ACCESS_KEY_ID=${access_key}
export AWS_SECRET_ACCESS_KEY=${secret_key}
export AWS_DEFAULT_REGION=${region}

#Update packages
apt update
# Install awscli - necessary to export join script to S3
sudo snap install aws-cli --classic
# add additional pacakges for https and curl, etc.
apt install apt-transport-https ca-certificates curl software-properties-common -y

# --------q---- INSTALL containerd!!!  - without Docker!
# install the container runtime only
# add docker gpg and repository
mkdir -p /etc/apt/keyrings/
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# you can either install docker completely or just a runtime like CRI-O or containerd (bundled with docker)
apt update
apt install docker.io -y

# Configure containerd to use systemd as the cgroup driver to use systemd cgroups.
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -e 's/SystemdCgroup = false/SystemdCgroup = true/g' -i /etc/containerd/config.toml
# apply the changes to containerd

#Update containerd to load the overlay and br_netfilter modules.
#The overlay module provides overlay filesystem support, which Kubernetes uses for its pod network abstraction
#enables bridge netfilter support in the Linux kernel, which is required for Kubernetes networking and policy
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Update kernel network settings to allow traffic to be forwarded for both IP4 and IP6. Required sysctl params, these persist across reboots.
tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
# Load the kernel modules
modprobe overlay
modprobe br_netfilter
# apply sysctl parameters without rebooting - to ensure they changes are used by the current system.
sysctl --system
systemctl restart containerd
systemctl enable containerd

# verify containerd is running
systemctl status containerd


## ------------------------------------ INSTALL Kubernetes tools ---------------------------------------------
# - kubeadm  - to bootstrap the cluster
# - kubelet  - to manage kubernetes objects on the machine
# - kubectl  - to interact with the cluster (CLI)

#Adding Kubernetes repositories
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update the repos
apt update
# Install the packages
apt install -y kubeadm=1.30.3-1.1 kubelet=1.30.3-1.1 kubectl=1.30.3-1.1
# lock the version 
apt-mark hold kubelet kubeadm kubectl
#Turn off swap
#If you run nodes with (traditional to-disk) swap, you lose a lot of the isolation properties that make sharing machines viable.
# You have no predictability around performance or latency or IO
# To avoid Kubernetes data such as contents of Secret object being written to tmpfs...
#  Swap support Version >= 1.28 https://kubernetes.io/blog/2023/08/24/swap-linux-beta/
# see https://kubernetes.io/docs/concepts/architecture/nodes/#swap-memory
swapoff -a
sudo sed -i '/swap/d' /etc/fstab
mount -a
ufw disable

# ----------------------
# enable kubelet
systemctl enable --now kubelet

#next line is getting EC2 instance IP, for kubeadm to initiate cluster
#we need to get EC2 internal IP address- default ENI is eth0
export ipaddr=`ip address|grep eth0|grep inet|awk -F ' ' '{print $2}' |awk -F '/' '{print $1}'`
export pubip=`dig +short myip.opendns.com @resolver1.opendns.com`

# the kubeadm init won't work until remove the containerd config and restart it.
# rm /etc/containerd/config.toml

systemctl restart containerd

# CRI-O ? ---- INSTALL critcl for debugging
export CRICTL_VERSION="v1.30.1"
export CRICTL_ARCH=$(dpkg --print-architecture)
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz
tar zxvf crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz
# verify crictl is installed
crictl version
# in case you need to set a different runtime endpoint:
# crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

# install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
bash get_helm.sh

# -------------------     Kubernetes cluster init ------------------------------------------------------------
#You can replace 172.16.0.0/16 with your desired pod networ
# apiserver-advertise-address - the IP address on which the API server is listening
# pod-network-cidr - sets the CIDR used fo the pod network
# 
kubeadm init --apiserver-advertise-address=$ipaddr --pod-network-cidr=192.168.0.0/16 --apiserver-cert-extra-sans=$pubip > /tmp/result.out
# kubeadm init --apiserver-advertise-address=$ipaddr --apiserver-cert-extra-sans=$pubip > /tmp/restult.out
cat /tmp/result.out

#this adds .kube/config for root account, run same for ubuntu user, if you need it
mkdir -p /root/.kube;
cp -i /etc/kubernetes/admin.conf /root/.kube/config;
cp -i /etc/kubernetes/admin.conf /tmp/admin.conf;
chmod 755 /tmp/admin.conf

--- end check optional ----------------
# Export the kubeconfig file so the root user can access the cluster.
export KUBECONFIG=/etc/kubernetes/admin.conf
#export KUBECONFIG=/root/.kube/config

# -------------------  CNI plugin installation -------------------------------------
# Kubernetes (version 1.3 through to the latest 1.32, and likely onwards) lets you use Container Network Interface (CNI) plugins for cluster networking.
# you can use Cilium, flannel, calico, etc.
#--------------------------------------------------------------------------------------------------------------------------
# FLANNEL
# Setup flannel
kubectl create ns kube-flannel
kubectl create --kubeconfig /root/.kube/config ns kube-flannel
kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged
helm repo add flannel https://flannel-io.github.io/flannel/
helm install flannel --set podCidr="192.168.0.0/16" --namespace kube-flannel flannel/flannel

# CALICO Cluster Pod Network
# curl -o /root/calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml
# sleep 5
# kubectl --kubeconfig /root/.kube/config apply -f /root/calico.yaml
# systemctl restart kubelet

# --------------------------------------------------------------------------------------
# Configure kubectl to connect to the cluster.
# Add kube config to ubuntu user.
mkdir -p /home/ubuntu/.kube;
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config;
chmod 755 /home/ubuntu/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


## ---- Configure Kubectl and Tools ------------------------------------------------------------
# install kubectl autocompletion
source <(kubectl completion bash) # set up autocomplete in bash into the current shell, bash-completion package should be installed first.
echo "source <(kubectl completion bash)" >> /home/ubuntu/.bashrc # add autocomplete permanently to your bash shell.
echo "source <(kubectl completion bash)" >> /root/.bashrc # add autocomplete permanently to your bash shell.

# add the alias for kubectl
echo "alias k='kubectl'" >> /home/ubuntu/.bashrc
echo "alias k='kubectl'" >> /root/.bashrc

# reload the bash profile
source ~/.bashrc
# echo "complete -o default -F __start_kubectl k" >> /home/ubuntu/.bashrc
# echo "complete -o default -F __start_kubectl k" >> /root/.bashrc
# complete -o default -F __start_kubectl k

# install jq for formatting output and strace for debugging
sudo apt install install jq strace -y

# install etcdctl
sudo apt install etcd-client -y

# configure vim to help editing the yaml files
cat <<EOF | tee -a ~/.vimrc
set tabstop=2
set expandtab
set shiftwidth=2
EOF

#create the join command from output
tail -2 /tmp/result.out > /tmp/join_command.sh;

#to copy kube config file to s3
aws s3 cp /tmp/join_command.sh s3://${s3_bucket_name};

# ---- Get ready to add nodes!
# Verify you can connect to the cluster
# If the node is listed as  "Ready", it means the CNI plugin is running and the control node is ready to accept workloads.
#kubectl get nodes

# print the join command
#kubeadm token create --print-join-command

#install ingress controller

# install NLB - ALB
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml
#validate
#kubectl get services ingress-nginx-controller --namespace=ingress-nginx
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
#kubectl apply -f k8s/nginx.yaml
