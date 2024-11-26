#!/bin/bash

# tunables
MIN_OBSERVE_TIME=5
MAX_OBSERVE_TIME=300
MAX_MIGRATE_TIME=300
AUTO_MIGRATE_TIME=5
WAIT_AFTER_MIGRATION=10

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

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

# get list of all cluster nodes except ariber
ALL_NODES=( $( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' | grep -v arbiter ) )
NODE_INDEX=0

# make sure cluster is healthy
wait_for_healthy_cluster

# balance VMs for each service group
for GROUP in $( grep service_group /var/lib/virtual/conf/*.xml | cut -d '>' -f 2 | cut -d '<' -f 1 | sort | uniq ); do

  echo ""
  echo "Solving service group $GROUP..."

  VM_CNT=0
  UNUSED_NODES=( $( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' | grep -v arbiter ) )

  # step 1. identify which nodes are NOT running VMs from this group
  for XML_FILE in $( grep "<service_group>$GROUP</service_group>" /var/lib/virtual/conf/*.xml -l ); do
    VM_CNT=$(( $VM_CNT + 1 ))

    # figure out vm name and uuid
    NAME=$( cluster_vm_name_from_xml "$XML_FILE" )
    VM=$( cluster_vm_id_from_xml "$XML_FILE" )

    # figure out where is vm running
    ACTIVE_NODE=$( cluster_vm_active_node "$VM" )
    [ "$ACTIVE_NODE" == "" ] && warn "- $NAME ($VM) not running!" && continue

    echo "- $NAME ($VM) running on $ACTIVE_NODE"
    UNUSED_NODES=($( echo "${UNUSED_NODES[@]}" | tr ' ' '\n' | grep -v $ACTIVE_NODE) )
    #XXX: this produces empty strings in array :/
    #UNUSED_NODES=("${UNUSED_NODES[@]/$ACTIVE_NODE}")
  done

  if [ ${#UNUSED_NODES[@]} -eq 0 ]; then
    warn "No valid migrations tagrets. Ignored group $GROUP!"
    continue
  fi

  echo "Valid migration targets are:"
  for NODE in "${UNUSED_NODES[@]}"; do
    echo "- $NODE"
  done

  # reset node useage count
  declare -A USAGE
  for NODE in ${ALL_NODES[@]}; do
    USAGE[$NODE]=0
  done

  # calculate migration ratio
  NODE_CNT=${#ALL_NODES[@]}
  RATIO=$(echo "scale=2; $VM_CNT / $NODE_CNT" | bc)
  RATIO_N=$(echo "scale=0; ($RATIO + 0.99) / 1" | bc)
  echo "Migration ratio is $RATIO (rounded $RATIO_N)"

  # step 2. if more than $RATIO_N vms are running, move them to empty nodes
  for XML_FILE in $( grep "<service_group>$GROUP</service_group>" /var/lib/virtual/conf/*.xml -l ); do
    # figure out vm name and uuid
    NAME=$( cluster_vm_name_from_xml "$XML_FILE" )
    VM=$( cluster_vm_id_from_xml "$XML_FILE" )

    # figure out where is vm running
    ACTIVE_NODE=$( cluster_vm_active_node "$VM" )
    [ "$ACTIVE_NODE" == "" ] && continue

    USAGE[$ACTIVE_NODE]=$(( ${USAGE[$ACTIVE_NODE]} + 1 ))
    if [ ${USAGE[$ACTIVE_NODE]} -gt $RATIO_N ]; then
      # migration target is round-robin from nodes with no vms running
      NEXT_NODE="${UNUSED_NODES[NODE_INDEX++ % ${#UNUSED_NODES[@]}]}"
      [[ "$NEXT_NODE" == "" ]] && warn "NO MIGRATION TARGETS!!" && continue
      echo "Evict $NAME ($VM) from $ACTIVE_NODE"
    else
      # skip migration if under migration ratio (#vms/#nodes)
      echo "Leave $NAME ($VM) running on $ACTIVE_NODE"
      continue
    fi

    if [[ "$ASK_FOR_CONFIRMATION" == true ]]; then
      # confirm migration
      read -p "Move $NAME to $NEXT_NODE? [Y/n] " cont
      if [[ $cont =~ ^[Yy]$ || $cont == "" ]]; then
        # continue with migration
        echo -n ""
      else
        # don't migrate
        echo "VM $NAME ($VM) left running on $ACTIVE_NODE"
        continue
      fi
    else
      # wait for 5 seconds and then continue
      echo -n "Will migrate $NAME to $NEXT_NODE in"
      for i in $(seq "$AUTO_MIGRATE_TIME" -1 1); do
        echo -n " $i"
        sleep 1
      done
    fi

    if [[ "$SIMULATE" == true ]]; then
      # simulate migration
      echo "Simulated crm res move ${VM}_vm $NEXT_NODE"
      sleep 1
    else
      # make sure cluster is healthy
      wait_for_healthy_cluster

      # request migration
      echo "Start migration"
      crm res move "${VM}_vm" $NEXT_NODE >/dev/null 2>/dev/null
      sleep $WAIT_AFTER_MIGRATION

      # make sure cluster is healthy (and wait for migration)
      wait_for_healthy_cluster
    fi
  done
done

# make sure cluster is clean when we're done
wait_for_healthy_cluster
