#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

ASK_FOR_CONFIRMATION=true
SIMULATE=false

usage() {
  cat <<EOF
Usage: $0 [options]

Redistribute workloads using VMs service_group attribute

Options:
  -a           Disable confirmation prompts (assume "yes")
  -s           Run in simulation (dry-run) mode
  -h, --help   Show this help and exit
EOF
}

# parse arguments
while getopts ":ash-" opt; do
  case ${opt} in
    a) ASK_FOR_CONFIRMATION=false ;;
    s) SIMULATE=true ;;
    h) usage; exit 0 ;;
    -)
      case "${OPTARG}" in
        help) usage; exit 0 ;;
        *) fail "Invalid option: --$OPTARG" ;;
      esac ;;
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

# get list of all cluster nodes
ALL_NODES=($( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' ))
NODE_INDEX=0

# make sure we have some target nodes
[ ${#ALL_NODES[@]} -eq 0 ] && fail "No valid migration targets!"
echo "Migration targets are ${ALL_NODES[@]}"

# make sure cluster is healthy
wait_for_healthy_cluster

# balance VMs for each service group
for GROUP in $( grep service_group /var/lib/virtual/conf/*.xml | cut -d '>' -f 2 | cut -d '<' -f 1 | sort | uniq ); do

  echo ""
  echo "Solving service group $GROUP..."

  VM_CNT=0
  UNUSED_NODES=( $( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' ) )

  # step 1. identify which nodes are NOT running VMs from this group
  for XML in $( grep "<service_group>$GROUP</service_group>" /var/lib/virtual/conf/*.xml -l ); do
    VM_CNT=$(( $VM_CNT + 1 ))

    # figure out vm name and fqdn
    FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || exit 1
    NAME=$( cluster_vm_name_from_xml "$XML" ) || exit 1

    # figure out where is vm running
    ACTIVE_NODE=$( cluster_vm_active_node "$NAME" )
    [ "$ACTIVE_NODE" == "" ] && warn "- $FQDN ($NAME) not running!" && continue

    echo "- $FQDN ($NAME) running on $ACTIVE_NODE"
    UNUSED_NODES=($( echo "${UNUSED_NODES[@]}" | tr ' ' '\n' | grep -v $ACTIVE_NODE) )
    #XXX: this produces empty strings in array :/
    #UNUSED_NODES=("${UNUSED_NODES[@]/$ACTIVE_NODE}")
  done

  if [ ${#UNUSED_NODES[@]} -eq 0 ]; then
    warn "No valid migrations tagrets. Ignored group $GROUP!"
    continue
  fi

  echo "Valid migration targets are ${UNUSED_NODES[@]}"

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
  for XML in $( grep "<service_group>$GROUP</service_group>" /var/lib/virtual/conf/*.xml -l ); do
    # figure out vm name and fqdn
    NAME=$( cluster_vm_name_from_xml "$XML" ) || exit 1
    FQDN=$( cluster_vm_fqdn_from_xml "$XML" ) || exit 1

    # check if VM is defined in corosync
    crm conf show | grep "${NAME}_vm" > /dev/null
    [ $? -ne 0 ] && warn "- $FQDN ($NAME) is not defined in corosync!!" && continue

    # figure out where is vm running
    ACTIVE_NODE=$( cluster_vm_active_node "$NAME" )
    [ "$ACTIVE_NODE" == "" ] && warn "- $FQDN ($NAME) is not running!!" && continue

    # determine if we should migrate VM as well as new node name
    USAGE[$ACTIVE_NODE]=$(( ${USAGE[$ACTIVE_NODE]} + 1 ))
    if [ ${USAGE[$ACTIVE_NODE]} -gt $RATIO_N ]; then
      # migration target is round-robin from nodes with no vms running
      NEXT_NODE="${UNUSED_NODES[NODE_INDEX++ % ${#UNUSED_NODES[@]}]}"
      [[ "$NEXT_NODE" == "" ]] && warn "NO MIGRATION TARGETS!!" && continue
      echo "Evict $FQDN ($NAME) from $ACTIVE_NODE"
    else
      # skip migration if under migration ratio (#vms/#nodes)
      echo "Leave $FQDN ($NAME) running on $ACTIVE_NODE"
      continue
    fi

    if [[ "$ASK_FOR_CONFIRMATION" == true ]]; then
      # confirm migration
      read -p "Move $FQDN to $NEXT_NODE? [Y/n] " cont
      if [[ $cont =~ ^[Yy]$ || $cont == "" ]]; then
        # continue with migration
        echo -n ""
      else
        # don't migrate
        echo "VM $FQDN ($NAME) left running on $ACTIVE_NODE"
        continue
      fi
    else
      # wait for 5 seconds and then continue
      echo -n "Will migrate $FQDN ($NAME) to $NEXT_NODE in"
      for i in $(seq "$AUTO_MIGRATE_TIME" -1 1); do
        echo -n " $i"
        sleep 1
      done
      echo ""
    fi

    if [[ "$SIMULATE" == true ]]; then
      # simulate migration
      echo "Simulated crm res move ${NAME}_vm $NEXT_NODE"
      sleep 1
    else
      # make sure cluster is healthy (and wait for migration)
      wait_for_healthy_cluster

      # request migration
      echo "Start migration"
      crm res move "${NAME}_vm" $NEXT_NODE >/dev/null 2>/dev/null
      sleep $WAIT_AFTER_MIGRATION

      # make sure cluster is healthy (and wait for migration)
      wait_for_healthy_cluster

      #XXX: add check if VM moved correctly
    fi
  done
done
