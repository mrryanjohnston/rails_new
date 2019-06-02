#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

instance_name="rails-new-template"
security_group_name="rails-new-template"
key_pair_name="rails-new-template-key"
key_pair_file="$HOME/.aws/rails-new-template-key.pem"
temporary_public_key_pair_file="$key_pair_file.pub"

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

printf "Looking for security group %s... " "$security_group_name"
security_group=$(aws ec2 describe-security-groups \
  --group-names "$security_group_name" 2> /dev/null |
  jq ".SecurityGroups | first(.[]).GroupId" -r)

if [ "$security_group" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Deleting security group %s... " "$security_group_name"
  while ! aws ec2 delete-security-group \
    --group-id "$security_group" 2> /dev/null
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
