#!/usr/bin/env bash

# Provided variables that are required: STACKNAME REGION CHEFNAME BUCKET
test -n "${STACKNAME}" || exit 1
test -n "${REGION}" || exit 1
test -n "${CHEFNAME}" || exit 1
test -n "${BUCKET}" || exit 1

#
# Chef reporting setup function
#

function setup_reporting_cleanup() {
  cat <<-EOF > /etc/cron.weekly/chef-reporting.cron
#!/usr/bin/env bash
REPORTING_MONTHS=3

log='/var/log/opscode-reporting/cull.log'

echo "[\$(date)] Deleting Chef Reporting events older than \${REPORTING_MONTHS} months" >> \$log
BEFORE=\$(date --date="\$(date +%Y-%m-15) -\${REPORTING_MONTHS} month" +'%Y-%m')
opscode-reporting-ctl remove-partitions --before \$BEFORE >> \$log 2>&1

echo >> \$log

exit 0

EOF
  chmod +x /etc/cron.weekly/chef-reporting.cron
}

#
# Chef client bootstrap
#

# Prepare chef-client bootstrap script
mkdir -p /etc/chef
cat > /etc/chef/bootstrap-chef_client.sh <<EOF
#!/usr/bin/env bash
if ! aws s3 ls ${BUCKET}/chef-client; then
  logger -p user.info 'No chef-client setup configuration'
  exit 0
fi

if ! aws s3 sync s3://${BUCKET}/chef-client/ /etc/chef/; then
  logger -p user.error -s 'Cannot retrieve chef-client configuration'
  exit -1
fi

chmod 0700 /etc/chef
if ! test -r /etc/chef/setup.sh; then
  logger -p user.info 'No chef-client setup.sh'
  exit 0
fi

if /bin/bash /etc/chef/setup.sh; then
  crontab -l | grep -v /etc/chef/bootstrap-chef_client.sh | crontab -
  rm /etc/chef/setup.sh /etc/chef/bootstrap-chef_client.sh
  logger -p user.info 'chef-client successfuly bootstraped'
  exit 0
fi

logger -p user.error -s 'chef-client bootstrap failed'
exit -1
EOF
chmod 00755 /etc/chef/bootstrap-chef_client.sh

# Setup cron job
RUN_AT=$(( ($(date +"%M") + 30) % 60 ))
crontab -l |
 { cat; echo "$RUN_AT * * * * /etc/chef/bootstrap-chef_client.sh"; } |
 crontab -

/etc/chef/bootstrap-chef_client.sh

# root email forwarding workaround for
# security issue with postfix unable to access /root/.forwarding
echo "root: $(cat /root/.forward)" >> /etc/aliases
newaliases

#
# Additional configuration depending on stack
#
case $STACKNAME in
  ${CHEFNAME}-AutomateStack-*)
    test -n "${AUTOMATENAME}" || exit 1
    # Configure administrative group (delayed in cron, as there is no listener yet)
    cat > /root/configure-admin.sh <<EOF
#!/usr/bin/env bash
curl -s \
  -H "api-token: gSkHK4qoAZdu2glDfytTiaTv6jk=" \
  -H "Content-Type: application/json" \
  -d '{"subjects":["team:saml:g01278424"], "action":"*", "resource":"*"}' \
  https://${AUTOMATENAME}/api/v0/auth/policies &&
  (
   crontab -l | grep -v /root/configure-admin.sh | crontab -
   rm /root/configure-admin.sh
   logger "Admin group configured"
  )
EOF
    chmod 00711 /root/configure-admin.sh
    crontab -l |
     { cat; echo "$RUN_AT * * * * /root/configure-admin.sh"; } |
     crontab -
  ;;
  ${CHEFNAME}-ChefServerStack-*)
    # Install and configure Chef reporting
    chef-server-ctl install opscode-reporting
    chef-server-ctl reconfigure
    opscode-reporting-ctl reconfigure --accept-license
    iid=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    if
      aws autoscaling describe-auto-scaling-instances --instance-ids=$iid --region $REGION |
      grep BootstrapAutoScaleGroup
    then # This is bootstrap instance (should be only one)
      setup_reporting_cleanup
    fi
    fqdn="${CHEFNAME}-server-${i}.${DOMAIN}"

  ;;
  ${CHEFNAME}-SupermarketStack-*)
  ;;
esac
