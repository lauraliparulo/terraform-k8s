
# Terraform plan to build a Kubernetes Cluster on AWS using EC2 instances

Inspired by 
- https://paulyu.dev/article/installing-kubernetes/
- https://github.com/Ahmad-Faqehi/Terraform-Bulding-K8S
- https://pswalia2u.medium.com/deploying-kubernetes-cluster-2ef2fbdd233a#:~:text=overlay%20%E2%80%94%20The%20overlay%20module%20provides,for%20Kubernetes%20networking%20and%20policy.
- https://daily.dev/blog/kubernetes-cni-comparison-flannel-vs-calico-vs-canal


## Create an RSA key pair
I have created the key pair for the instance directly on the console and downloaded the private key .pem file.
You can create the key pair under the section "EC2 > Network & Security > Key Pairs". Choose the "RSA" type and ".pem" format for SSH.

To connect to ssh, you need to change the permissions on the file, otherwise aws won't let you connect to the instance. So you first have to run:
> chmod 400 "<your-key-name>.pem" 

And then :
> ssh -i "kube-private-key.pem" ubuntu@ec2-13-60-29-125.eu-north-1.compute.amazonaws.com


## -Run terraform commands with local sensitive variables.

As we are placing the credentials in the .tfvars file, you need to run your terraform command with the options "-var-file", for example:
> terraform plan -var-file="variables.tfvars"


# WIP - coming soon!