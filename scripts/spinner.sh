spinner=(
"Waiting for the EC2 Instances K8s cluster setup    "
""Waiting for the EC2 Instances K8s cluster setup .   "
""Waiting for the EC2 Instances K8s cluster setup ..  "
""Waiting for the EC2 Instances K8s cluster setup ... "
""Waiting for the EC2 Instances K8s cluster setup ...."
""Waiting for the EC2 Instances K8s cluster setup ....."
)

max=$((SECONDS + 300))

while [[ ${SECONDS} -le ${max} ]]
do
    for item in ${spinner[*]}
    do
        echo -en "\r$item"
        sleep .1
        echo -en "\r              \r"
    done
done