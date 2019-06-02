#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ami_name="rails-new-template"

printf "Looking for AMI %s... " "$ami_name"
ami=$(aws ec2 describe-images \
  --filters "Name=name,Values=$ami_name" "Name=is-public,Values=false" |
  jq ".Images | first(.[]).ImageId" -r)

if [ "$ami" == '' ]
then
  echo -e "${RED}Nope.${NC}"
else
  echo -e "${GREEN}Yep!${NC}"

  printf "Deregistering AMI %s... " "$ami_name"

  if ! aws ec2 deregister-image --image-id "$ami"
  then
    echo -e "${RED}Nope.${NC}"
  else
    echo -e "${GREEN}Yep!${NC}"

    printf "Deleting snapshot that backed AMI %s... " "$ami_name"

    if ! aws ec2 describe-snapshots \
      --filter="Name=description,Values=*$ami*" > /dev/null
    then
      echo -e "${RED}Nope.${NC}"
    else
      echo -e "${GREEN}Yep!${NC}"
    fi
  fi
fi

