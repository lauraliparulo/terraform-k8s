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
apt install -y containerd.io

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
# initialize the master node
# enable kubelet
systemctl enable --now kubelet

kubeadm config images pull --cri-socket unix:///run/containerd/containerd.sock


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

kubeadm init --apiserver-advertise-address=$ipaddr --pod-network-cidr=192.168.0.0/16 --apiserver-cert-extra-sans=$pubip > /tmp/result.out
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
# kubectl create ns kube-flannel
# kubectl create --kubeconfig /root/.kube/config ns kube-flannel
# kubectl label --overwrite ns kube-flannel pod-security.kubernetes.io/enforce=privileged
# helm repo add flannel https://flannel-io.github.io/flannel/
# helm install flannel --set podCidr="192.168.0.0/16" --namespace kube-flannel flannel/flannel

# CALICO Cluster Pod Network
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
kubectl get pods --all-namespaces
kubectl get nodes -o wide

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



# Install ALB Ingress controller

# install ALB ingress controller
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/main/docs/install/iam_policy.json

IAM_CREATE_POLICY_ARN=$(aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document file://iam_policy.json --output text --query Policy.Arn)

echo $IAM_CREATE_POLICY_ARN

aws iam attach-role-policy --policy-arn $IAM_CREATE_POLICY_ARN --role-name ssm_ec2_role

#Install cert-manager so that you can inject the certificate configuration into the webhooks. Use Kubernetes 1.16 or later to run the following command:
#https://artifacthub.io/packages/helm/cert-manager/cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io --force-update
kubectl create namespace cert-manager
# helm install cert-manager --namespace cert-manager --version v1.16.2 jetstack/cert-manager
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.16.2/cert-manager.yaml

helm repo add eks https://aws.github.io/eks-charts
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=kubernetes-admin@kubernetes --set region=eu-north1 --set vpcId=${vpc_id}
#helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=kubernetes-admin@kubernetes

#kubectl logs -n kube-system $(kubectl get po -n kube-system | egrep -o alb-ingress[a-zA-Z0-9-]+)
kubectl -n kube-system describe deployment/aws-load-balancer-controller
kubectl -n kube-system describe endpoints/aws-load-balancer-webhook-service