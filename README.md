
# Terraform plan to build a Kubernetes Cluster on AWS using EC2 instances

Inspired by 
- https://paulyu.dev/article/installing-kubernetes/
- https://github.com/Ahmad-Faqehi/Terraform-Bulding-K8S
- https://pswalia2u.medium.com/deploying-kubernetes-cluster-2ef2fbdd233a#:~:text=overlay%20%E2%80%94%20The%20overlay%20module%20provides,for%20Kubernetes%20networking%20and%20policy.
- https://daily.dev/blog/kubernetes-cni-comparison-flannel-vs-calico-vs-canal
- https://github.com/sandervanvugt/cka/blob/master/setup-container.sh
- https://mrmaheshrajput.medium.com/deploy-kubernetes-cluster-on-aws-ec2-instances-f3eeca9e95f1


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


# check logs
tail -f /var/log/syslog

## debug cluster
crictl logs -f  $(crictl ps | grep etcd | awk '{print $1}')


# Nrtwork policy for Flannel
https://dev.to/jmarhee/network-policies-with-canal-and-flannel-on-k3s-11oe

Or try Calico! Or Weave!


# install SSM manager plugin

https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-debian-and-ubuntu.html


# CHECK ALB
https://aws.amazon.com/de/blogs/opensource/kubernetes-ingress-aws-alb-ingress-controller/

 
sudo less /var/log/amazon/ssm/amazon-ssm-agent.log


cluster_ip=$(kubectl get svc foo-service -ojsonpath='{.spec.clusterIP}')
echo $cluster_ip

# --------------
type load balancer - it will ask the cloud provider to create a load balancer for your service where the the load balancer is availablein the public subnet

ALB will be created for you from AWS - AWS will charge for each LOad Balancer created! And you don't have much control (in terms of security)

Ingress is an alternative to this! Ingress solves the exact problem

- Ingress resource on K8s
- Ingress Controller - Nginx Controller
- Load Balancer  (not very flexible) - so we use a declarative Ignress resource yaml 

We deploy the ignress controller which reads the Ingress resource and creates the LB according to the configuration

1) deploy ingress controller
2) deploy ingress resource
3) a load blaancer will be created



# 
Follow this tutorial - get it done!!!
https://www.youtube.com/watch?v=kf3UjITS91M