#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$DOMAIN" ] || [ -z "$IP" ]
then
   echo "You must call this with DOMAIN and IP environment variables set."
   echo ""
   echo "IP=\"127.0.0.1\" DOMAIN=\"ryjo.codes\" ./lib/scripts/create_environment.sh"
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
ip="$(whatismyip)"
security_group_ec2_name="rails-new-$environment-ec2"
security_group_ec2_description="Rails New $environment ec2"
security_group_efs_name="rails-new-$environment-efs"
security_group_efs_description="Rails New $environment EFS Mount Target"
key_pair_file="$HOME/.aws/rails-new-$environment-key.pem"
temporary_public_key_pair_file="$key_pair_file.pub"
key_pair_name="rails-new-$environment-key"
base_ami_name="rails-new-template"
instance_name="rails-new-$environment"
file_system_creation_token=RailsNew"$environment"FileSystem
file_system_name="rails-new-$environment-file-system"
image_name="rails-new-$environment-template"
version=$(dpkg-parsechangelog -S version 2> /dev/null)
built_deb_file="rails-new_${version}_all.deb"

printf "The environment you'll create with this script... "
echo -e "${GREEN}$environment${NC}"

printf "The domain you'll create with this script... "
echo -e "${GREEN}$dns_entry${NC}"

printf "The IP you'll use for this script... "
echo -e "${GREEN}$IP${NC}"
printf "Your detected IP (from DuckDuckGo)... "
detected_ip=$(curl -fs "https://api.duckduckgo.com/?q=ip&format=json" | jq -r '.Answer' | awk '{print $5}')
echo -e "${GREEN}$detected_ip${NC}"

printf "Looking for security group %s... " "$security_group_ec2_name"

security_group_ec2=$(aws ec2 describe-security-groups \
  --group-names "$security_group_ec2_name" 2> /dev/null)

if [ "$security_group_ec2" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Creating security group %s... " "$security_group_ec2_name"

  security_group_ec2=$(aws ec2 create-security-group \
    --group-name "$security_group_ec2_name" \
    --description "$security_group_ec2_description")

  if [ "$security_group_ec2" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to create security group."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
    security_group_ec2=$(aws ec2 describe-security-groups \
      --group-names "$security_group_ec2_name" 2> /dev/null)
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

security_group_ec2=$(jq -r '.SecurityGroups | first(.[])' <<< "$security_group_ec2")
security_group_ec2_id=$(jq ".GroupId" -r <<< "$security_group_ec2")

printf "Looking for ingress rule for ssh access on security group %s... " "$security_group_ec2_name"
if [ "$(jq '.IpPermissions | .[] | select(.FromPort==22 and .ToPort==22 and .IpProtocol=="tcp")' <<< "$security_group_ec2")" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Allowing ssh via ingress rules for security group %s... " "$security_group_ec2_name"

  if ! aws ec2 authorize-security-group-ingress \
    --group-id "$security_group_ec2_id" \
    --cidr "$IP"/24 \
    --port 22 \
    --protocol tcp
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to apply ingress rule for ssh to security group."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

printf "Looking for ingress rule for ssh access on security group %s... " "$security_group_ec2_name"
if [ "$(jq '.IpPermissions | .[] | select(.FromPort==80 and .ToPort==80 and .IpProtocol=="tcp")' <<< "$security_group_ec2")" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Allowing http via ingress rules for security group %s... " "$security_group_ec2_name"

  if ! aws ec2 authorize-security-group-ingress \
    --group-id "$security_group_ec2_id" \
    --cidr "$IP"/24 \
    --port 80 \
    --protocol tcp
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to apply ingress rule for http to security group."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

printf "Looking for security group %s... " "$security_group_efs_name"

security_group_efs=$(aws ec2 describe-security-groups \
  --group-names "$security_group_efs_name" 2> /dev/null)

if [ "$security_group_efs" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Creating security group %s... " "$security_group_efs_name"

  security_group_efs=$(aws ec2 create-security-group \
    --group-name "$security_group_efs_name" \
    --description "$security_group_efs_description")

  if [ "$security_group_efs" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to create security group."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
    security_group_efs=$(aws ec2 describe-security-groups \
      --group-names "$security_group_efs_name" 2> /dev/null)
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

security_group_efs=$(jq -r '.SecurityGroups | first(.[])' <<< "$security_group_efs")
security_group_efs_id=$(jq ".GroupId" -r <<< $security_group_efs)

printf "Looking for ingress rule for ssh access on security group %s... " "$security_group_efs_name"
if [ "$(jq '.IpPermissions | .[] | select(.FromPort==2049 and .ToPort==2049 and .IpProtocol=="tcp")' <<< "$security_group_efs")" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Allowing nfs via ingress rules for security group %s... " "$security_group_efs_name"

  if ! aws ec2 authorize-security-group-ingress \
    --group-id "$security_group_efs_id" \
    --source-group "$security_group_ec2_id" \
    --port 2049 \
    --protocol tcp
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to apply ingress rule for nfs to security group."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

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

printf "Looking for file system %s... " "$file_system_name"

file_system_id=$(aws efs describe-file-systems \
  --creation-token "$file_system_creation_token" |
  jq '.FileSystems | first(.[]) | .FileSystemId' -r)

if [ "$file_system_id" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Creating file system %s... " "$file_system_name"

  file_system_id=$(aws efs create-file-system \
    --creation-token "$file_system_creation_token" \
    --tags "Key=Name,Value=$file_system_name" |
    jq '.FileSystemId' -r)

  if [ "$file_system_id" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to create file system."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
else
  echo -e "${YELLOW}Found.${NC}"
fi

printf "Looking for default subnet... "

subnet=$(aws ec2 describe-subnets \
  --filters='Name=default-for-az,Values=true' |
  jq -r '.Subnets | first(.[]).SubnetId')
if [ "$subnet" == '' ]
then
  echo -e "${RED}Nope.${NC}"
  echo "Failed to start new instance."
  exit 1
else
  echo -e "${YELLOW}Found.${NC}"
fi

printf "Looking for mount target for file system... "
mount_target_ip=$(aws efs describe-mount-targets \
  --file-system-id "$file_system_id" |
  jq 'first(.MountTargets[]) | select(.IpAddress!=null) | .IpAddress' -r)

if [ "$mount_target_ip" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  printf "Creating mount target for file system... "
  while [ "$mount_target_ip" == '' ]
  do
    sleep 1
    mount_target_ip=$(aws efs create-mount-target \
      --file-system-id "$file_system_id" \
      --security-group "$security_group_efs_id" \
      --subnet-id "$subnet" 2> /dev/null |
      jq '.IpAddress' -r)
  done

  echo -e "${GREEN}Yep!${NC}"
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
  ami=$(aws ec2 describe-images \
    --filters "Name=name,Values=$base_ami_name" "Name=is-public,Values=false" |
    jq ".Images | first(.[]).ImageId" -r)

  if [ "$ami" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed find base ami name $base_ami_name."
    exit 1
  else
    echo -e "${YELLOW}Found.${NC}"
  fi

  printf "Starting instance %s... " "$instance_name"

  instance_id=$(aws ec2 run-instances \
    --image-id "$ami" \
    --count 1 \
    --instance-type t2.micro \
    --key-name "$key_pair_name" \
    --security-group-ids "$security_group_ec2_id" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name},{Key=version,Value=$version}]" |
    jq '.Instances | first(.[]).InstanceId' -r)

  if [ "$instance_id" == '' ]
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to start new instance."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi

printf "Waiting for instance %s to come up so we can get its IP address... " "$instance_name"
while [ "$instance_ip_address" == "" ]
do
  sleep 1
  instance_ip_address=$(aws ec2 describe-instances \
    --filters "Name=instance-id,Values=$instance_id" "Name=instance-state-name,Values=running" |
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

function nginx_config() {
  cat << CONFIG
server {
  listen 80;
  server_name "$dns_entry";
  root /usr/lib/rails-new/public;
  index index.html index.htm;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_redirect off;
  }
}
CONFIG
}

printf "Installing nfs-common and mounting file system... "

if ! ssh -i "$key_pair_file" ubuntu@"$instance_ip_address" \
  "sudo apt-get -qqy install nfs-common > /dev/null 2>&1;
  sudo mkdir -p /var/lib/rails-new/db
  sudo mount \
  -t nfs \
  -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
  $mount_target_ip:/ /var/lib/rails-new/db;
  sudo tee /etc/nginx/sites-enabled/default <<< \"$(nginx_config)\" > /dev/null;
  sudo service nginx restart;"
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to ssh in to $instance_ip_address."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi

  printf "Looking for base AMI %s... " "$image_name"
  ami=$(aws ec2 describe-images \
    --filters "Name=name,Values=$image_name" "Name=is-public,Values=false" |
    jq ".Images | first(.[]).ImageId" -r)

  if [ "$ami" != '' ]
  then
    echo -e "${YELLOW}Found.${NC}"
  else
    echo -e "${YELLOW}Nope.${NC}"

    printf "Creating AMI %s... " "$image_name"
    if ! aws ec2 create-image \
      --instance-id "$instance_id" \
      --name "$image_name" > /dev/null
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to create AMI $image_name."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi

printf "Building rails-new... "
if ! debuild --no-tgz-check > /dev/null 2>&1
then
  echo -e "${RED}Nope.${NC}"
  echo "Failed to build rails-new."
  exit 1
else
  echo -e "${GREEN}Yep!${NC}"
  echo "Version of deb file... $version"

  printf "Copying ../$built_deb_file file to instance... "

  if ! scp -i "$key_pair_file" "../$built_deb_file" ubuntu@"$instance_ip_address":~ > /dev/null
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to copy ../$built_deb_file file to instance."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"

    printf "Installing rails-new on instance... "

    if ! ssh -i "$key_pair_file" ubuntu@"$instance_ip_address" \
      "sudo dpkg -i $built_deb_file > /dev/null 2>&1;
      sleep 5;
      cd /usr/lib/rails-new;
      sudo /usr/bin/rails-production db:create > /dev/null 2>&1;"
    then
      echo -e "${RED}Nope.${NC}"
      echo "Failed to install rails-new on instance."
      exit 1
    else
      echo -e "${GREEN}Yep!${NC}"
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

  printf "Checking if DNS entry is pointed at instance ip %s... " "$instance_ip_address"
  dns_record_for_instance_ip_address=$(jq -r ".ResourceRecords[] | .Value==\"$instance_ip_address\"" <<< "$dns_record")

  if [ "$dns_record_for_instance_ip_address" == 'false' ]
  then
    echo -e "${YELLOW}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
  exit 0
fi

function jsontemplate() {
  cat << JSON 
{
  "HostedZoneId": "$hz",
  "ChangeBatch": {
    "Comment": "",
    "Changes": [
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "$dns_entry",
          "Type": "A",
          "SetIdentifier": "Rails New $environment",
          "Region": "us-east-1",
          "TTL": 0,
          "ResourceRecords": [
            {
              "Value": "$instance_ip_address"
            }
          ]
        }
      }
    ]
  }
}
JSON
}

printf "Creating DNS entry %s... " "$dns_entry"

if ! aws route53 change-resource-record-sets \
  --cli-input-json "$(jsontemplate)" > /dev/null
then
  echo -e "${RED}Nope.${NC}"
  echo "Failed to create DNS entry."
  exit 1
else
  echo -e "${GREEN}Yep!${NC}"
fi
