#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

# attemt to name every vm xml file
for XML in /var/lib/virtual/conf/*.xml; do
  # get VM name from config xml
  NAME=$( cluster_vm_name_from_xml "$XML" ) || exit 1
  FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || exit 1

  # check if VM is defined in corosync
  crm conf show | grep "${NAME}_vm" > /dev/null
  [ $? -ne 0 ] && warn "$FQDN ($NAME) is not defined in corosync!" && continue

  # figure out where is vm running
  ACTIVE_NODE=$( cluster_vm_active_node "$NAME" )
  [ "$ACTIVE_NODE" == "" ] && warn "$FQDN ($NAME) is not running!!" && continue

  # print vm name
  echo "$FQDN ($NAME) running on $ACTIVE_NODE"
done
