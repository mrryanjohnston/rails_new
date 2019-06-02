#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

key_pair_file="$HOME/.aws/rails-new-template-key.pem"
temporary_public_key_pair_file="$key_pair_file.pub"
key_pair_name="rails-new-template-key"
security_group_name="rails-new-template"
instance_name="rails-new-template"
base_ami_name="rails-new-template"

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

printf "Looking for security group %s... " "$security_group_name"
security_group=$(aws ec2 describe-security-groups \
  --group-names "$security_group_name" 2> /dev/null)

if [ "$security_group" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"
  printf "Checking ingress rule for ssh access on security group %s... " "$security_group_name"

  if [ "$(jq '.SecurityGroups | .[].IpPermissions | .[] | .FromPort == 22 and .ToPort == 22 and .IpProtocol == "tcp"' <<< "$security_group")" == 'true' ]
  then
    echo -e "${GREEN}Found.${NC}"
  else
    echo -e "${RED}Nope.${NC}"
  fi
fi

printf "Looking for instance %s... " "$instance_name"
instance=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$instance_name" |
  jq -r '.Reservations | .[]')

if [ "$instance" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"

  printf "State of instance %s... " "$instance_name"
  echo "$instance" | jq '.Instances | first(.[]).State.Name'
fi

printf "Looking for base AMI %s... " "$base_ami_name"
ami=$(aws ec2 describe-images \
  --filters "Name=name,Values=$base_ami_name" "Name=is-public,Values=false")

if [ "$(jq -r '.Images[]' <<< $ami)" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Found.${NC}"

  printf "Base AMI's status is... "
  jq 'first(.Images[]).State' <<< $ami
fi
