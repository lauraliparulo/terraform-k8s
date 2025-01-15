#!/bin/bash

######### ** FOR WORKER NODE ** #########

hostname k8s-worker-${worker_number}
echo "k8s-worker-${worker_number}" > /etc/hostname

export AWS_ACCESS_KEY_ID=${access_key}
export AWS_SECRET_ACCESS_KEY=${secret_key}
export AWS_DEFAULT_REGION=${region}

#Update packages
apt update
# Install awscli (optional)
sudo snap install aws-cli --classic
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


# the kubeadm init won't work entel remove the containerd config and restart it.
#rm /etc/containerd/config.toml
systemctl restart containerd

sysctl --system

# to insure the join command start when the installion of master node is done.
sleep 2m

aws s3 cp s3://${s3_bucket_name}/join_command.sh /tmp/.
chmod +x /tmp/join_command.sh
bash /tmp/join_command.sh

# Label worker node
# kubectl label node  <host-name>  node-role.kubernetes.io/worker=wo