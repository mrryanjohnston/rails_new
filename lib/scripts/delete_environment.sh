#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$DOMAIN" ]
then
   echo "You must call this with the DOMAIN environment variable set."
   echo ""
   echo "DOMAIN=\"ryjo.codes\" ./lib/scripts/delete_environment.sh"
   echo ""
   echo "Or, even better, set it in your .bashrc (or similar) file!"
   exit 1
fi

if [ -z "$1" ]
then
  environment="production"
  dns_entry="rails-new.$DOMAIN."
else
  environment="$1"
  dns_entry="rails-new-$environment.$DOMAIN."
fi

key_pair_file="$HOME/.aws/rails-new-$environment-key.pem"
temporary_public_key_pair_file="$key_pair_file.pub"
key_pair_name="rails-new-$environment-key"
security_group_ec2_name="rails-new-$environment-ec2"
security_group_efs_name="rails-new-$environment-efs"
file_system_name="rails-new-$environment-file-system"
file_system_creation_token=RailsNew"$environment"FileSystem
instance_name="rails-new-$environment"
ami_name="rails-new-$environment-template"

printf "Looking for (running) instance %s... " "$instance_name"
instance_id=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$instance_name" "Name=instance-state-name,Values=running" |
  jq ".Reservations[].Instances | first(.[]) | .InstanceId" -r)
if [ "$instance_id" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Terminating instance %s... " "$instance_name"

  if ! aws ec2 terminate-instances --instance-ids "$instance_id" > /dev/null
  then
    echo -e "${YELLOW}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi

printf "Looking for file system %s... " "$file_system_name"
file_system_id=$(aws efs describe-file-systems \
  --creation-token "$file_system_creation_token" |
  jq '.FileSystems | first(.[]) | .FileSystemId' -r)
if [ "$file_system_id" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"
  printf "Looking for mount target for file system... "
  mount_target_id=$(aws efs describe-mount-targets \
    --file-system-id "$file_system_id" |
    jq 'first(.MountTargets[]).MountTargetId' -r)

  if [ "$mount_target_id" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"
    printf "Deleting mount target... "
    
    if ! aws efs delete-mount-target \
      --mount-target-id "$mount_target_id"
    then
      echo -e "${RED}Nope.${NC}"
    else
      echo -e "${GREEN}Yep!${NC}"
    fi
  fi

  printf "Deleting file system %s... " "$file_system_name"

  while ! aws efs delete-file-system \
    --file-system-id "$file_system_id" > /dev/null 2>&1
  do
    sleep 1
  done
  echo -e "${GREEN}Yep!${NC}"
fi

printf "Looking for security group %s... " "$security_group_efs_name"
security_group_efs=$(aws ec2 describe-security-groups \
  --group-names "$security_group_efs_name" 2> /dev/null |
  jq -r "first(.SecurityGroups[]) | .GroupId")

if [ "$security_group_efs" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Deleting security group %s... " "$security_group_efs_name"
  while ! aws ec2 delete-security-group \
    --group-id "$security_group_efs" 2> /dev/null
  do
    sleep 1
  done

  echo -e "${GREEN}Yep!${NC}"
fi

printf "Looking for security group %s... " "$security_group_ec2_name"
security_group_ec2=$(aws ec2 describe-security-groups \
  --group-names "$security_group_ec2_name" 2> /dev/null |
  jq ".SecurityGroups | first(.[]).GroupId" -r)

if [ "$security_group_ec2" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Deleting security group %s... " "$security_group_ec2_name"
  while ! aws ec2 delete-security-group \
    --group-id "$security_group_ec2" 2> /dev/null
  do
    sleep 1
  done

  echo -e "${GREEN}Yep!${NC}"
fi

printf "Deleting key pair %s... " "$key_pair_name"
if ! aws ec2 delete-key-pair \
  --key-name "$key_pair_name"
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"
fi

printf "Deleting local ssh key file %s... " "$key_pair_file"
if ! rm -f "$key_pair_file"
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"
fi

printf "Deleting temporary public key file %s... " "$temporary_public_key_pair_file"
if ! rm -f "$temporary_public_key_pair_file"
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"
fi

printf "Looking for AMI %s... " "$ami_name"
ami=$(aws ec2 describe-images \
  --filters "Name=name,Values=$ami_name" "Name=is-public,Values=false" |
  jq ".Images | first(.[]).ImageId" -r)

if [ "$ami" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Deregistering AMI %s... " "$ami_name"

  if ! aws ec2 deregister-image --image-id "$ami"
  then
    echo -e "${RED}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"

    printf "Looking for snapshot of ami %s... " "$ami_name"

    if ! snapshot_id=$(aws ec2 describe-snapshots \
      --filter="Name=description,Values=*$ami*")
    then
      echo -e "${YELLOW}Nope.${NC}"
    else
      echo -e "${YELLOW}Found.${NC}"
      # No idea why I have to do this
      snapshot_id=$(jq -r 'first(.Snapshots[]).SnapshotId' <<< "$snapshot_id")

      printf "Deleting snapshot that backed AMI %s... " "$ami_name"
      if ! aws ec2 delete-snapshot \
        --snapshot-id "$snapshot_id" > /dev/null
      then
        echo -e "${RED}Nope.${NC}"
      else
        echo -e "${GREEN}Yep!${NC}"
      fi
    fi
  fi
fi

printf "Looking for DNS entry %s... " "$dns_entry"
hz=$(aws route53 list-hosted-zones | jq -r '.HostedZones[0].Id')
dns_record=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$hz" |
  jq -r ".ResourceRecordSets[] | select (.Name==\"$dns_entry\")")

if [ "$dns_record" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"

  function jsontemplate() {
    cat << JSON 
{
  "HostedZoneId": "$hz",
  "ChangeBatch": {
    "Comment": "",
    "Changes": [
      {
        "Action": "DELETE",
        "ResourceRecordSet": $dns_record
      }
    ]
  }
}
JSON
  }


  printf "Deleting DNS entry %s... " "$dns_entry"
  if ! aws route53 change-resource-record-sets \
    --cli-input-json "$(jsontemplate)" > /dev/null 2>&1
  then
    echo -e "${YELLOW}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi
