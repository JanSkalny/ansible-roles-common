#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

echo -n "Cluster status is: "
case "$(check_status)" in
  f) echo "Failed resources" ;;
  m) echo "Migrating resources" ;;
  o) echo "Monitoring resources" ;;
  S) echo "Fencing in progress" ;;
  "") echo "OK" ;;
  *) echo "Unknown" ;;
esac
echo ""

# attempt to name every running vm on this node, and make sure it's clusterified
echo "Looking for local VMs that are not handled by corosync..."
for NAME in $( virsh list | grep running | awk '{print $2}'); do
  # get VM name from config xml
  XML=$( cluster_xml_from_vm_name "$NAME" ) || continue
  FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || continue

  # check if VM is defined in corosync
  echo "$CRM_CONF" | grep "${NAME}_vm" >/dev/null
  [ $? -ne 0 ] && warn "- $FQDN ($NAME) is undefined!!" 
done
echo ""

# attemt to name every vm xml file
echo "Make sure all VMs declared in XML files are defined in corosync and running..."
for XML in /var/lib/virtual/conf/*.xml; do
  # figure out vm xml file and fqdn
  NAME=$( cluster_vm_name_from_xml "$XML" ) || continue
  FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || continue

  # check if VM is defined in corosync
  echo "$CRM_CONF" | grep "${NAME}_vm" >/dev/null
  [ $? -ne 0 ] && warn "- $FQDN ($NAME) is not defined in corosync!!" && continue

  # figure out where is vm running
  ACTIVE_NODE=$( cluster_vm_active_node "$NAME" ) 
  [ "$ACTIVE_NODE" == "" ] && warn "- $FQDN ($NAME) is not running!!" && continue
  
  # print vm name
  #echo "- $FQDN running on $ACTIVE_NODE"
done
