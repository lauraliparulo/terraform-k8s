#!/usr/bin/env bash

# Script to run a shell script on a Linux instance

while getopts "r:i:" opt; do
  case $opt in
    r) regionId="$OPTARG" ;;
    i) instanceId="$OPTARG" ;;
    *) echo "Usage: $0 -r region_id -i instance_id command"
       exit 1
       ;;
  esac
done

# Remove the flags from the positional parameters
shift $((OPTIND -1))

# Check if regionId and instanceId are provided
if [[ -z "$regionId" || -z "$instanceId" ]]; then
  echo "Usage: $0 -r region_id -i instance_id command"
  exit 1
fi

cmdId=$(aws ssm send-command --document-name "AWS-RunShellScript" --targets "Key=instanceids,Values=$instanceId" --region "$regionId" --output text --parameters commands="'$*'" | grep -Eo '([a-z0-9])+-([a-z0-9])+-([a-z0-9])+-([a-z0-9])+-([a-z0-9])+')
[ $? -ne 0 ] && { echo "Failed to send command"; exit 1; }

while [ "$(aws ssm list-command-invocations --region "$regionId" --command-id "$cmdId" --query "CommandInvocations[].Status" --output text)" == "InProgress" ]; do
  sleep 0.5
done

aws ssm list-command-invocations --region "$regionId" --command-id "$cmdId" --details --query "CommandInvocations[*].CommandPlugins[*].Output[]" --output text 