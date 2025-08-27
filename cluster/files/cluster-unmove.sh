#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

for RES in $( echo "$CRM_CONF" | grep 'cli-prefer' | awk '{print $3}' ); do
  echo "unmove $RES"
  #read -p "Press Enter to continue..."
  crm res clear $RES
done
