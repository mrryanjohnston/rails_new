#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ip="$(whatismyip)"
key_pair_file="$HOME/.aws/rails-new-template-key.pem"
temporary_public_key_pair_file="$key_pair_file.pub"
key_pair_name="rails-new-template-key"
security_group_name="rails-new-template"
security_group_description="Rails New Template"
base_ami_name="ubuntu/images/hvm-ssd/ubuntu-cosmic-18.10-amd64-server*"
instance_name="rails-new-template"
ami_name="rails-new-template"

printf "The IP you'll use for this script... "
echo -e "${GREEN}$ip${NC}"
printf "Your detected IP (from DuckDuckGo)... "
detected_ip=$(curl -fs "https://api.duckduckgo.com/?q=ip&format=json" | jq -r '.Answer' | awk '{print $5}')
echo -e "${GREEN}$detected_ip${NC}"

printf "Looking for local key pair %s... " "$key_pair_file"
if [ -e "$key_pair_file" ]
then
  echo -e "${YELLOW}Found.${NC}"

  printf "Looking for key pair %s on AWS... " "$key_pair_name"
  if aws ec2 describe-key-pairs \
    --key-names "$key_pair_name" > /dev/null 2>&1
  then
    echo -e "${YELLOW}Found.${NC}"
  else
    echo -e "${YELLOW}Nope.${NC}"
    read -r -p "We found $key_pair_file locally, but did not find $key_pair_name on AWS. Upload $key_pair_file to AWS? (Y/n): " should_upload
    should_upload=$(tr '[:lower:]' '[:upper:]' <<< ${should_upload:-Y})

    if [ "$should_upload" == "Y" ]
    then
      printf "Creating temporary public key file %s... " "$temporary_public_key_pair_file"

      if ! ssh-keygen -y \
        -f "$key_pair_file" \
        > "$temporary_public_key_pair_file" 2>&1 
      then
        echo -e "${RED}Nope.${NC}"
        echo "Failed to create public key file $temporary_public_key_pair_file."
        exit 1
      else
        echo -e "${GREEN}Yep!${NC}"
      fi

      printf "Uploading temporary public key file %s to AWS... " "$temporary_public_key_pair_file"
      if ! aws ec2 import-key-pair \
        --key-name "$key_pair_name" \
        --public-key-material file://"$temporary_public_key_pair_file" \
        > /dev/null 2>&1
      then
        echo -e "${RED}Nope.${NC}"
        echo "Failed to upload temporary public key file $temporary_public_key_pair_file to AWS."
        exit 1
      else
        echo -e "${GREEN}Yep!${NC}"
      fi
    fi
  fi
else
  echo -e "${YELLOW}Nope.${NC}"

  printf "Looking for key pair %s on AWS... " "$key_pair_name"
  if aws ec2 describe-key-pairs \
    --key-names "$key_pair_name" > /dev/null 2>&1
  then
    echo -e "${YELLOW}Found.${NC}"
  else
    echo -e "${YELLOW}Nope.${NC}"

    printf "Creating key pair %s... " "$key_pair_file"

    if ! aws ec2 create-key-pair \
      --key-name "$key_pair_name" \
      --query 'KeyMaterial' \
      --output text \
      > "$key_pair_file"
    then
      echo -e "${RED}Nope.${NC}"
      echo "Failed to create key pair. One called $key_pair_name might already exist."
      exit 1
    else
      echo -e "${GREEN}Yep!${NC}"
    fi
    chmod 400 "$key_pair_file"
  fi
fi

printf "Looking for security group %s... " "$security_group_name"

security_group=$(aws ec2 describe-security-groups \
  --group-names "$security_group_name" 2> /dev/null)

if [ "$security_group" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"

  printf "Creating security group %s... " "$security_group_name"

  security_group=$(aws ec2 create-security-group \
    --group-name "$security_group_name" \
    --description "$security_group_description")

  if [ "$security_group" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to create security group $security_group_name."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
    security_group=$(aws ec2 describe-security-groups \
      --group-names "$security_group_name" 2> /dev/null)
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

security_group=$(jq -r '.SecurityGroups | first(.[])' <<< "$security_group")
security_group_id=$(jq -r '.GroupId' <<< "$security_group")

printf "Looking for ingress rule for ssh access on security group %s... " "$security_group_name"
if [ "$(jq '.IpPermissions | .[] | select(.FromPort==22 and .ToPort==22 and .IpProtocol=="tcp")' <<< "$security_group")" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Allowing ssh via ingress rules for security group %s... " "$security_group_name"

  if ! aws ec2 authorize-security-group-ingress \
    --group-id "$security_group_id" \
    --cidr "$ip"/24 \
    --port 22 \
    --protocol tcp
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to apply ingress rules to security group."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

printf "Looking for (running) instance %s... " "$instance_name"
instance_id=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$instance_name" "Name=instance-state-name,Values=running" |
  jq ".Reservations[].Instances | first(.[]) | .InstanceId" -r)

if [ "$instance_id" != '' ]
then
  echo -e "${YELLOW}Found.${NC}"
else
  echo -e "${YELLOW}Nope.${NC}"

  printf "Finding base AMI %s... " "$base_ami_name"
  base_ami=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,
      Values=$base_ami_name" |
    jq '.Images | sort_by(.CreationDate) | last(.[]) | .ImageId' -r)

  if [ "$base_ami" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed find base ami name $base_ami_name."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi

  printf "Starting instance %s... " "$instance_name"

  instance_id=$(aws ec2 run-instances \
    --image-id "$base_ami" \
    --count 1 \
    --instance-type t2.micro \
    --key-name "$key_pair_name" \
    --security-group-ids "$security_group_id" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" |
    jq '.Instances | first(.[]).InstanceId' -r)

  if [ "$instance_id" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to start new instance."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi

  printf "Waiting for instance %s to come up so we can get its IP address... " "$instance_name"
  while [ "$instance_ip_address" == "" ]
  do
    sleep 1
    instance_ip_address=$(aws ec2 describe-instances \
      --instance-ids "$instance_id" \
      --filters "Name=instance-state-name,Values=running" |
      jq ".Reservations[].Instances | first(.[]) | .PublicIpAddress" -r)
  done
  echo -e "${GREEN}Yep!${NC}"

  printf "Now we sleep for 1 minute, waiting for network interface to be up... "
  sleep 1m
  echo -e "${GREEN}Yep!${NC}"

  printf "Adding %s to list of known ssh hosts... " "$instance_ip_address"

  if ! ssh-keyscan -H "$instance_ip_address" >> "$HOME/.ssh/known_hosts" 2> /dev/null
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to add $instance_ip_address to list of known ssh hosts."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi

  printf "Updating instance and installing dependencies... "

  if ! ssh -i "$key_pair_file" ubuntu@"$instance_ip_address" "sudo apt-get -qq update > /dev/null 2>&1;
    sudo apt-get -qqy upgrade > /dev/null 2>&1;
    sudo apt-get -qqy install ruby nodejs bundler zlib1g-dev libsqlite3-dev nginx > /dev/null 2>&1;"
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to ssh in to $instance_ip_address."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi

  printf "Removing previous ssh keys... "
  if ! ssh -i ~/.aws/rails-new-template-key.pem ubuntu@"$instance_ip_address" \
    "sudo shred -u /etc/ssh/*_key /etc/ssh/*_key.pub;
     echo '' > ~/.ssh/authorized_keys"
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to remove ssh keys from the system."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi

printf "Looking for base AMI %s... " "$ami_name"
ami=$(aws ec2 describe-images \
  --filters "Name=name,Values=$ami_name" "Name=is-public,Values=false" |
  jq ".Images | first(.[]).ImageId" -r)

if [ "$ami" != '' ]
then
  echo -e "${YELLOW}Found.${NC}"
else
  echo -e "${YELLOW}Nope.${NC}"

  printf "Creating AMI %s... " "$ami_name"
  if ! aws ec2 create-image \
    --instance-id "$instance_id" \
    --name "$ami_name" > /dev/null
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to create AMI $ami_name."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi
