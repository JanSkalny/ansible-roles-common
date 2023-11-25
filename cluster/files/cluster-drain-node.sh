#!/bin/bash

warn() {
  echo "$*" 1>&2
}

fail() {
  echo "$*" 1>&2
  exit 1
}

# list of all cluster nodes except our node
NODES=$( crm status | grep -oP 'Online: \[\K[^\]]+' )
HOSTNAME=$(hostname -s)
NODES=(${NODES[@]/$HOSTNAME})
NODE_INDEX=0

for VM in $( virsh list | grep running | awk '{print $2}'); do
  # get VM name from config xml
  UUID=$(virsh dumpxml "$VM" | xmllint --xpath 'string(/domain/uuid/text())' -)
  [ -z "$UUID" ] && fail "$VM does not have uuid?"
  XML_FILE=$(grep -l "<name>$VM</name>" /var/lib/virtual/conf/*.xml)
  [ -f "$XML_FILE" ] || fail "$VM does not have XML file"
  NAME=$(cat "$XML_FILE" | xmllint --xpath '/domain/metadata/fqdn/text()' - 2>/dev/null)
  [ -z "$NAME" ] && fail "$VM does not have a fqdn defined in its metadata!"

  # check if VM is defined in corosync
  crm conf show | grep "${VM}_vm" > /dev/null
  [ $? -ne 0 ] && warn "$NAME ($VM) is not defined in corosync!" && continue

  # round-robin all cluster nodes when migrating
  NEXT_NODE="${NODES[NODE_INDEX++ % ${#NODES[@]}]}"

  # confirm migration
  echo "Migrate $NAME to $NEXT_NODE?"
  read -p "Press Enter to continue..."

  # request migration
  crm res move "${VM}_vm" $NEXT_NODE > /dev/null

  # observe migration process
  for I in $( seq 1 300 ); do
    sleep 1
    STATUS=$( virsh list | grep $VM | awk '{print $3}')
    virsh list | grep $VM > /dev/null

    # stop waiting
    if [ $? -eq 1 ]; then
      echo " migrated!"
      echo ""
      break
    fi
    echo -n "${STATUS:0:1}"
  done

  # if still running, migration failed
  virsh list | grep $UUID > /dev/null
  [ $? -eq 1 ] || echo " failed!"done
done
