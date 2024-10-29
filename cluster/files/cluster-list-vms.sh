#!/bin/bash

warn() {
  echo "$*" 1>&2
}

fail() {
  echo "$*" 1>&2
  exit 1
}

# attempt to name every running vm on this node
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

  # print vm name
  echo "$NAME ($VM)"
done
