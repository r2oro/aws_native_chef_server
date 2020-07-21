#!/usr/bin/env bash
#
# Provided variables that are required: STACKNAME CHEFNAME BUCKET REGION
#
test -n "${STACKNAME}" || exit 1
test -n "${CHEFNAME}" || exit 1
test -n "${BUCKET}" || exit 1
test -n "${REGION}" || exit 1

#
# Settings
#

# DNS Setup
DOMAIN=cloud.health.ge.com
CreateCnameURL=http://cloudview.digital.ge.com/createcname_ttl60
DeleteCnameURL=http://cloudview.digital.ge.com/deletecname
CreateAnameURL=http://cloudview.digital.ge.com/createdns_ttl60
DeleteAnameURL=http://cloudview.digital.ge.com/deletedns

#
# AMI clenaup
#

# Delete backdoor keys
sed -i '/CLOUD-image-gesos/d;/packer_/d' /home/gecloud/.ssh/authorized_keys

#
# Delete non-existing eth0 config file if interface does not exist
#

if
  (! ifconfig -a | grep eth0) && [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]
then
  rm -f /etc/sysconfig/network-scripts/ifcfg-eth0
  kill $(cat /var/run/dhclient.pid)
  rm -f /var/run/dhclient.pid
  /sbin/dhclient
fi


# Delete IPv6 localhost
sed -i '/^::1/d' /etc/hosts

#
# Istall necessary packages missing on AMI
#

# AWSCLI
rpm -q epel-release || yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
rpm -q awscli || yum install -y awscli

# AWS cfn-init
rpm -q aws-cfn-bootstrap || yum install -y https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.amzn1.noarch.rpm
for i in `/bin/ls -1 /opt/aws/bin/`; do ln -s /opt/aws/bin/$i /usr/bin/ ; done
# Setup aditional package path (as AWSCLI install places modules in directory not checked by default)
mkdir -p /root/.local/lib/python2.7
ln -s /usr/local/lib/python2.7/site-packages/ /root/.local/lib/python2.7

# Install dig
rpm -q bind-utils || yum install -y bind-utils

#
# Setup hostname and regeister it in DNS depending on STACKNAME
#

# Register instance A record

# Determine desired FQDN
case $STACKNAME in
  ${CHEFNAME}-AutomateStack-*)
    fqdn="${CHEFNAME}-automate-i.${DOMAIN}"
  ;;
  ${CHEFNAME}-ChefServerStack-*)
    iid=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    if
      aws autoscaling describe-auto-scaling-instances --instance-ids=$iid --region $REGION |
      grep BootstrapAutoScaleGroup
    then # This is bootstrap instance (should be only one)
      i="i"
    else # This is general frontend instance (can't assign number, make it unique)
      i=$iid
    fi
    fqdn="${CHEFNAME}-server-${i}.${DOMAIN}"
  ;;
  ${CHEFNAME}-SupermarketStack-*)
    fqdn="${CHEFNAME}-supermarket-i.${DOMAIN}"
  ;;
esac

# Register A record for desired FQDN
existingip=$(dig $fqdn | awk "/^$fqdn\.\s.*\sIN\s+A\s/ "'{print $5}')
if [ -n "$existingip" ]; then
  curl -s ${DeleteAnameURL}?fqdn=${fqdn}\&ipaddress=$existingip
fi
curl -s ${CreateAnameURL}?fqdn=${fqdn}\&ipaddress=$(hostname -I)

# Change name of the server
HOSTNAME=$(echo $fqdn | sed 's/\..*$//')
sed -i "/$(hostname)/d" /etc/hosts
echo "$(hostname -I) $HOSTNAME $fqdn" >> /etc/hosts
hostnamectl set-hostname --static $HOSTNAME
echo 'preserve_hostname: true' >> /etc/cloud/cloud.cfg

# Create aditional DNS CNAMES (optional)
test -z "${DNSSETUP}"  && exit 0
for entry in $DNSSETUP; do
  NAME=${entry%:*}
  TARGET=${entry#*:}
  cname=$(dig ${NAME} |
    awk "/^${NAME}\..*\sIN\s+CNAME\s/"' {print $5}')
  if [ -z "$cname" ]; then
    curl -s ${CreateCnameURL}/${NAME}/${TARGET}
  elif [ $cname != ${TARGET}. ]; then
    curl -s ${DeleteCnameURL}/${NAME}
    curl -s ${CreateCnameURL}/${NAME}/${TARGET}
  fi
done
# Wait until they are available
for entry in $DNSSETUP; do
  NAME=${entry%:*}
  TARGET=${entry#*:}
  cname=$(dig ${NAME} |
    awk "/^${NAME}\..*\sIN\s+CNAME\s/"' {print $5}')
  # Delay needed due to InfoBlox propagation
  while [[ $cname != ${TARGET}. ]]; do
    echo "$NAME not properly defined, waiting"
    sleep 30
    cname=$(dig ${NAME} |
      awk "/^${NAME}\..*\sIN\s+CNAME\s/"' {print $5}')
  done
done
