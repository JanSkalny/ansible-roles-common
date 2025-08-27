#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

echo -n "Cluster status is: "
case "$(check_status)" in
  f) echo "Failed" ;;
  m) echo "Migrating" ;;
  o) echo "Monitoring" ;;
  "") echo "OK" ;;
  *) echo "Unknown" ;;
esac
echo ""

# attempt to name every running vm on this node, and make sure it's clusterified
echo "VMs running on this node..."
for NAME in $( virsh list | grep running | awk '{print $2}'); do
  # get VM name from config xml
  XML=$( cluster_xml_from_vm_name "$NAME" ) || exit 1
  FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || exit 1

  # check if VM is defined in corosync
  crm conf show | grep "${NAME}_vm" > /dev/null
  [ $? -ne 0 ] && warn "- $FQDN ($NAME) is not defined in corosync!!" && continue

  # print vm name
  echo "- $FQDN"
done
echo ""

# attemt to name every vm xml file
echo "VMs defined in XML files..."
for XML in /var/lib/virtual/conf/*.xml; do
  # figure out vm xml file and fqdn
  NAME=$( cluster_vm_name_from_xml "$XML" ) || exit 1
  FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || exit 1

  # check if VM is defined in corosync
  crm conf show | grep "${NAME}_vm" > /dev/null
  [ $? -ne 0 ] && warn "- $FQDN ($NAME) is not defined in corosync!!" && continue

  # figure out where is vm running
  ACTIVE_NODE=$( cluster_vm_active_node "$NAME" ) || exit 1
  [ "$ACTIVE_NODE" == "" ] && warn "- $FQDN ($NAME) is not running!!" && continue
  
  # print vm name
  echo "- $FQDN running on $ACTIVE_NODE"
done
