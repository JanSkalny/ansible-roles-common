#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

# attemt to name every vm xml file
for XML in /var/lib/virtual/conf/*.xml; do
  # figure out vm xml file and fqdn
  NAME=$( cluster_vm_name_from_xml "$XML" ) || continue
  FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || continue

  # check if VM is defined in corosync
  echo "$CRM_CONF" | grep "${NAME}_vm" >/dev/null
  [ $? -ne 0 ] && warn "$XML ($FQDN) not defined in corosync"
done
