#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ip="$(whatismyip)"
if [ -z "$1" ]
then
  environment="production"
  dns_entry="rails-new.ryjo.codes."
else
  environment="$1"
  dns_entry="rails-new-$environment.ryjo.codes."
fi

security_group_ec2_name="rails-new-$environment-ec2"
key_pair_name="rails-new-$environment-key"
key_pair_file="$HOME/.aws/rails-new-$environment-key.pem"
image_name="rails-new-$environment-template"
instance_name="rails-new-$environment"
version=$(dpkg-parsechangelog -S version 2> /dev/null)
built_deb_file="rails-new_${version}_all.deb"

printf "The IP you'll use for this script... "
echo -e "${GREEN}$ip${NC}"
printf "Your detected IP (from DuckDuckGo)... "
echo -e "${GREEN}$(whatismyip)${NC}"

printf "Looking for DNS entry %s... " "$dns_entry"
hz=$(aws route53 list-hosted-zones | jq -r '.HostedZones[0].Id')
dns_record=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$hz" |
  jq -r ".ResourceRecordSets[] | select (.Name==\"$dns_entry\")")

if [ "$dns_record" == '' ]
then
  echo -e "${YELLOW}Nope.${NC}"
  echo "There is no DNS record for $dns_entry. Please run the create_environment script first."
  exit 1
else
  echo -e "${GREEN}Found.${NC}"

  dns_entry_instance_ip=$(jq -r '.ResourceRecords[].Value' <<< "$dns_record")
  echo "$dns_entry is pointed to $dns_entry_instance_ip."
fi

printf "Building rails-new version %s... " "$version"
if ! debuild --no-tgz-check > /dev/null 2>&1
then
  echo -e "${RED}Nope.${NC}"
  echo "Failed to build rails-new."
  exit 1
else
  echo -e "${GREEN}Yep!${NC}"
fi


printf "Looking for base AMI %s... " "$image_name"
ami=$(aws ec2 describe-images \
  --filters "Name=name,Values=$image_name" "Name=is-public,Values=false" |
  jq ".Images | first(.[]).ImageId" -r)

if [ "$ami" == '' ]
then
  echo -e "${RED}Nope.${NC}"
  echo "Could not find ami. Exiting..."
  exit 1
else
  echo -e "${GREEN}Found.${NC}"
fi

printf "Looking for security group %s... " "$security_group_ec2_name"

security_group_ec2=$(aws ec2 describe-security-groups \
  --group-names "$security_group_ec2_name" 2> /dev/null)

if [ "$security_group_ec2" == '' ]
then
  echo -e "${RED}Nope.${NC}"
  echo "Could not find security group."
  exit 1
else
  echo -e "${GREEN}Found.${NC}"
fi

security_group_ec2=$(jq -r '.SecurityGroups | first(.[])' <<< "$security_group_ec2")
security_group_ec2_id=$(jq ".GroupId" -r <<< "$security_group_ec2")

printf "Looking for ingress rule for ssh access on security group %s... " "$security_group_ec2_name"
if [ "$(jq '.IpPermissions | .[] | select(.FromPort==22 and .ToPort==22 and .IpProtocol=="tcp")' <<< "$security_group_ec2")" == '' ]
then
  echo -e "${RED}Nope.${NC}"
  echo "Security group doesn't have the right ingress rules"
  exit 1
else
  echo -e "${GREEN}Found.${NC}"
fi

printf "Looking for ingress rule for ssh access on security group %s... " "$security_group_ec2_name"
if [ "$(jq '.IpPermissions | .[] | select(.FromPort==80 and .ToPort==80 and .IpProtocol=="tcp")' <<< "$security_group_ec2")" == '' ]
then
  echo -e "${RED}Nope.${NC}"
  echo "Security group doesn't have the right ingress rules"
  exit 1
else
  echo -e "${GREEN}Found.${NC}"
fi

printf "Looking for local key pair %s... " "$key_pair_file"
if [ -e "$key_pair_file" ]
then
  echo -e "${GREEN}Found.${NC}"
else
  echo -e "${RED}Nope.${NC}"
  echo "You can't create an instance for this without the ssh keys."
  exit 1
fi

printf "Looking for key pair %s on AWS... " "$key_pair_name"
if aws ec2 describe-key-pairs \
  --key-names "$key_pair_name" > /dev/null 2>&1
then
  echo -e "${GREEN}Found.${NC}"
else
  echo -e "${RED}Nope.${NC}"
  echo "Key pair not found on AWS."
  exit 1
fi

printf "Starting instance %s for version %s... " "$instance_name" "$version"

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
fi

echo -e "${GREEN}Yep!${NC}"

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
    sudo /usr/bin/rails-production db:migrate > /dev/null 2>&1;
    sudo service rails-new restart"
  then
    echo -e "${RED}Nope.${NC}"
    echo "Failed to install rails-new on instance."
    exit 1
  else
    echo -e "${GREEN}Yep!${NC}"
  fi
fi

function jsontemplate() {
  cat << JSON 
{
  "HostedZoneId": "$hz",
  "ChangeBatch": {
    "Comment": "",
    "Changes": [
      {
        "Action": "UPSERT",
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

printf "Updating DNS entry %s... " "$dns_entry"

if ! aws route53 change-resource-record-sets \
  --cli-input-json "$(jsontemplate)" > /dev/null
then
  echo -e "${RED}Nope.${NC}"
  echo "Failed to create DNS entry."
  exit 1
else
  echo -e "${GREEN}Yep!${NC}"
fi
