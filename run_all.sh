#terraform apply -auto-approve -var-file="variables_aws.tfvars"
./spinner.sh
#aws ec2-instance-connect ssh --instance-id i-08f0a131af2b4e33d
#./run_on_ec2.sh -i i-ec2_instance_master -r eu-north-1 "netstat -tuln | awk \'{print \$4}\'"


MASTER_NODE_NAME=$(terraform output instance_master_instance_id)

MASTER_NODE_INSTANCE_ID=$(echo "${MASTER_NODE_NAME}" | tr --delete \")

BUCKET_NAME=$(terraform output s3_bucket_name)

BUCKET_ID=$(echo "${BUCKET_NAME}" | tr --delete \")

aws ssm start-session --target $MASTER_NODE_INSTANCE_ID  --region eu-north-1


# ubuntu@k8s-master-1:~$ sudo usermod -a -G ubuntu ssm-user
# ubuntu@k8s-master-1:~$ sudo usermod -a -G adm ssm-user
# ubuntu@k8s-master-1:~$ sudo usermod -a -G sudo ssm-user
# ubuntu@k8s-master-1:~$ sudo usermod -a -G dip ssm-user
# ubuntu@k8s-master-1:~$ sudo usermod -a -G lxd ssm-user

sudo runuser -l ubuntu -c 'kubectl create deploy nginx666 --image=nginx --replicas=4'
sudo runuser -l ubuntu -c 'kubectl expose deployment nginx666 --type=NodePort --port=80 --target-port=8080'

# aws s3 cp s3://$BUCKET_ID/nginx.yaml nginx.yaml

# aws ssm send-command \
#     --instance-ids "i-0023f4b8182d5096c" \
#     --document-name "AWS-RunShellScript" \
#     --comment "IP config" \
#     --parameters 'commands=["echo Hello world"]' 

# aws ssm send-command \
#     --instance-ids "i-0023f4b8182d5096c" \
#     --document-name "AWS-RunShellScript" \
#     --comment "IP config" \
#     --parameters 'commands=["kubectl apply -f nginx.yaml"]' 


#     aws ssm send-command \
#     --instance-ids "i-0023f4b8182d5096c" \
#     --document-name "AWS-RunShellScript" \
#     --comment "IP config" \
#     --parameters 'commands=["kubectl create deployment nginx5 --image=nginx --replicas=4"]' 

