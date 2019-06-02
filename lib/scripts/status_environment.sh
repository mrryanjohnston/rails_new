#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$1" ]
then
  environment="production"
  dns_entry="rails-new.ryjo.codes."
else
  environment="$1"
  dns_entry="rails-new-$environment.ryjo.codes."
fi

key_pair_file="$HOME/.aws/rails-new-$environment-key.pem"
temporary_public_key_pair_file="$key_pair_file.pub"
key_pair_name="rails-new-$environment-key"
security_group_ec2_name="rails-new-$environment-ec2"
security_group_efs_name="rails-new-$environment-efs"
file_system_name="rails-new-$environment-file-system"
file_system_creation_token=RailsNew"$environment"FileSystem
instance_name="rails-new-$environment"
image_name="rails-new-$environment-template"

printf "Looking for local key pair %s... " "$key_pair_file"
if [ -e "$key_pair_file" ]
then
  echo -e "${GREEN}Found.${NC}"
else
  echo -e "${RED}Nope.${NC}"
fi

printf "Looking for local public key file %s... " "$temporary_public_key_pair_file"
if [ -e "$temporary_public_key_pair_file" ]
then
  echo -e "${GREEN}Found.${NC}"
else
  echo -e "${RED}Nope.${NC}"
fi

printf "Looking for key pair %s on AWS... " "$key_pair_name"
if aws ec2 describe-key-pairs \
  --key-names "$key_pair_name" > /dev/null 2>&1
then
  echo -e "${GREEN}Found.${NC}"
else
  echo -e "${RED}Nope.${NC}"
fi

printf "Looking for security group %s... " "$security_group_ec2_name"
security_group_ec2=$(aws ec2 describe-security-groups \
  --group-names "$security_group_ec2_name" 2> /dev/null)

if [ "$security_group_ec2" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"
  printf "Checking ingress rule for ssh access on security group %s... " "$security_group_ec2_name"

  case "$(jq '.SecurityGroups | .[].IpPermissions | .[] | .FromPort == 22 and .ToPort == 22 and .IpProtocol == "tcp"' <<< "$security_group_ec2")" in
    *'true'*)
      echo -e "${GREEN}Found.${NC}"
      ;;
    *)
      echo -e "${RED}Nope.${NC}"
      ;;
  esac

  printf "Checking ingress rule for http access on security group %s... " "$security_group_ec2_name"
  case "$(jq '.SecurityGroups | .[].IpPermissions | .[] | .FromPort == 80 and .ToPort == 80 and .IpProtocol == "tcp"' <<< "$security_group_ec2")" in
    *'true'*)
      echo -e "${GREEN}Found.${NC}"
      ;;
    *)
      echo -e "${RED}Nope.${NC}"
      ;;
  esac
fi

printf "Looking for security group %s... " "$security_group_efs_name"
security_group_efs=$(aws ec2 describe-security-groups \
  --group-names "$security_group_efs_name" 2> /dev/null)

if [ "$security_group_efs" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"
  printf "Checking ingress rule for ssh access on security group %s... " "$security_group_efs_name"

  if [ "$(jq '.SecurityGroups | .[].IpPermissions | .[] | .FromPort == 2049 and .ToPort == 2049 and .IpProtocol == "tcp"' <<< "$security_group_efs")" == 'true' ]
  then
    echo -e "${GREEN}Found.${NC}"
  else
    echo -e "${RED}Nope.${NC}"
  fi
fi

printf "Looking for file system %s... " "$file_system_name"

file_system_id=$(aws efs describe-file-systems \
  --creation-token "$file_system_creation_token" |
  jq '.FileSystems | first(.[]) | .FileSystemId' -r)

if [ "$file_system_id" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Looking for mount target for file system... "
  mount_target_id=$(aws efs describe-mount-targets \
    --file-system-id "$file_system_id" |
    jq '.MountTargetId' -r)

  if [ "$mount_target_id" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi

printf "Looking for image %s... " "$image_name"
ami=$(aws ec2 describe-images \
  --filters "Name=name,Values=$image_name" "Name=is-public,Values=false" |
  jq ".Images | first(.[]).ImageId" -r)

if [ "$ami" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"
fi

printf "Looking for instance %s... " "$instance_name"
instance=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$instance_name" |
  jq -r '.Reservations[].Instances | first(.[])')

if [ "$instance" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"

  echo "State of instances:"
  echo "$instance" | jq '"\(.InstanceId) \(.Tags[] | select(.Key=="version").Value) \(.PublicIpAddress) \(.State.Name)"'
fi
instance_ip_address=$(jq -r 'select(.PublicIpAddress!=null) | .PublicIpAddress' <<< "$instance")

printf "Looking for DNS entry %s... " "$dns_entry"
hz=$(aws route53 list-hosted-zones | jq -r '.HostedZones[0].Id')
dns_record=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$hz" |
  jq -r ".ResourceRecordSets[] | select (.Name==\"$dns_entry\")")

if [ "$dns_record" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"

  printf "Checking if DNS entry is pointed at instance ip %s... " "$instance_ip_address"
  dns_record_for_instance_ip_address=$(jq -r ".ResourceRecords[] | .Value==\"$instance_ip_address\"" <<< "$dns_record")

  if [ "$dns_record_for_instance_ip_address" == 'false' ]
  then
    echo -e "${RED}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi
