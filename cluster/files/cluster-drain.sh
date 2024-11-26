#!/bin/bash

# tunables
MIN_OBSERVE_TIME=10
MAX_OBSERVE_TIME=300
MAX_MIGRATE_TIME=300
AUTO_MIGRATE_TIME=5
WAIT_AFTER_MIGRATION=10

. /usr/local/bin/cluster-tools.sh

IGNORE_HOST=$( hostname -s )
ASK_FOR_CONFIRMATION=true
SIMULATE=false

# parse arguments
while getopts ":as" opt; do
  case ${opt} in
    a) ASK_FOR_CONFIRMATION=false ;;
    s) SIMULATE=true ;;
    \?) fail "Invalid option: -$OPTARG" ;;
  esac
done
shift $((OPTIND -1))

# adjust timers when running simulation
if [[ "$SIMULATE" == true ]]; then
  echo "Running in simulation mode"
  MIN_OBSERVE_TIME=1
  WAIT_AFTER_MIGRATION=3
fi

# remainder is ignore host (defaults to hostname -s)
if [[ ! -z "$1" ]]; then
    IGNORE_HOST="$1"
fi

# get list of all cluster ndoes except ariber and IGNORE_HOST provided
NODES=($( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' | grep -v arbiter | grep -v "$IGNORE_HOST" ))
NODE_INDEX=0

# make sure we have some target nodes
[ ${#NODES[@]} -eq 0 ] && fail "No valid migration targets!"
echo "Migration targets are ${NODES[@]}"

for VM in $( virsh list | grep running | awk '{print $2}'); do
  # make sure cluster is healthy
  wait_for_healthy_cluster

  # get VM name from config xml
  UUID=$(virsh dumpxml "$VM" | xmllint --xpath 'string(/domain/uuid/text())' -)
  [ -z "$UUID" ] && fail "$VM does not have uuid?"
  XML_FILE=$(grep -l "<name>$VM</name>" /var/lib/virtual/conf/*.xml)
  [ -f "$XML_FILE" ] || fail "$VM does not have XML file"
  NAME=$( cluster_vm_name_from_xml "$XML_FILE" )

  # check if VM is defined in corosync
  crm conf show | grep "${VM}_vm" > /dev/null
  [ $? -ne 0 ] && warn "$NAME ($VM) is not defined in corosync!" && continue

  # round-robin all cluster nodes when migrating
  NEXT_NODE="${NODES[NODE_INDEX++ % ${#NODES[@]}]}"

  if [[ "$ASK_FOR_CONFIRMATION" == true ]]; then
    # confirm migration
    echo "Migrate $NAME to $NEXT_NODE?"
    read -p "Press Enter to continue..."
  else
    # wait for 5 seconds and then continue
    echo -n "Will migrate $NAME to $NEXT_NODE in"
    for i in $(seq "$AUTO_MIGRATE_TIME" -1 1); do
      echo -n " $i"
      sleep 1
    done
    echo ""
  fi

  if [[ "$SIMULATE" == true ]]; then
    # simulate migration
    echo "simulated crm res move ${VM}_vm $NEXT_NODE"
    sleep 1
  else
    # request migration
	echo -n "Starting migration... "
    crm res move "${VM}_vm" $NEXT_NODE > /dev/null 2>/dev/null

    # observe migration process
    for I in $( seq 1 $MAX_MIGRATE_TIME ); do
      sleep 1
      STATUS=$( virsh list | grep $VM | awk '{print $3}')
      virsh list | grep $VM > /dev/null

      # stop waiting
      if [ $? -eq 1 ]; then
        echo " migrated!"
        sleep $WAIT_AFTER_MIGRATION
        break
      fi
	  echo -n "${STATUS:0:1}"
    done

    # if still running, migration failed
    virsh list | grep $UUID > /dev/null
    [ $? -eq 1 ] || echo " failed!"
  fi
done
