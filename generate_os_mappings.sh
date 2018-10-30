#!/bin/bash

# get the latest Name value from:
# RHEL: aws ec2 describe-images --owners 309956199498 --filters "Name=name,Values=RHEL-7.6*" --query "Images[*].Name" --output text
# CentOS highperf: `aws ec2 describe-images --owners 446539779517 --filters "Name=name,Values=chef-highperf-centos7*" --query "Images[*].Name" | sort`

# RHEL_RELEASE='RHEL-7.6_HVM_BETA-20180814-x86_64-0-Hourly2-GP2'
# CENTOS_RELEASE='chef-highperf-centos7-201808171554'

# Query GESOS Enterprise Cloud Build AMIs
RHEL_RELEASE='GESOS-Cloud-RHEL7'
CENTOS_RELEASE='GESOS-Cloud-CentOS7'

printf "Mappings:\n  AMI:\n"

regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)
for region in $regions; do
  rhel_ami=$(aws --region $region ec2 describe-images \
  --owners 277688789493 \
  --filters "Name=name,Values=${RHEL_RELEASE}*" \
  --query "Images[*].[CreationDate,Name,ImageId]" --output "text" | sort -r | head -1 | awk '{print $3}')

  centos_ami=$(aws --region $region ec2 describe-images \
  --owners 277688789493 \
  --filters "Name=name,Values=${CENTOS_RELEASE}*" \
  --query "Images[*].[CreationDate,Name,ImageId]" --output "text" | sort -r | head -1 | awk '{print $3}')

  [ -n "$rhel_ami" -o -n "$centos_ami" ] && printf "    $region:\n"
  [ -n "$rhel_ami" ] && printf "      rhel: $rhel_ami\n"
  [ -n "$centos_ami" ] && printf "      centos: $centos_ami\n"
done
