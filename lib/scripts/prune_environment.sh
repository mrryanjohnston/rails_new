#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$DOMAIN" ]
then
   echo "You must call this with the DOMAIN environment variable set."
   echo ""
   echo "DOMAIN=\"ryjo.codes\" ./lib/scripts/prune_environment.sh"
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

instance_name="rails-new-$environment"

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

echo "Looking for instances that aren't $dns_entry_instance_ip... "
instance_ids=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$instance_name" "Name=instance-state-name,Values=running" |
  jq ".Reservations[].Instances[] | select(.PublicIpAddress==\"$dns_entry_instance_ip\" | not) | .InstanceId" -r | tr "\n" " ")

echo "Terminating instances $instance_ids... "
aws ec2 terminate-instances --instance-ids $instance_ids
