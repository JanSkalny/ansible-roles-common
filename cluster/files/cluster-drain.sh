#!/bin/bash

# get common functions from cluster-tools.sh
. /usr/local/bin/cluster-tools.sh

DRAIN_FROM=$( hostname -s )
ASK_FOR_CONFIRMATION=true
SIMULATE=false

usage() {
  cat <<'EOF'
Usage: cluster-drain.sh [options] [FILTER]

Safely migrate VMs from selected node(s).

Notes:
- provide FILTER (defaults to `hostname -s`) to migrate from multiple hosts.
- only online nodes are considered valid migration targets.
- `service_group` requirements are ignored when draining nodes, instead 
  round-robin is used. Use `cluster-balance.sh` to rebalance if required.

Options:
  -a           Disable confirmation prompts (assume "yes")
  -s           Run in simulation (dry-run) mode
  -h, --help   Show this help and exit

Examples:
  cluster-drain.sh                      # migrate from current host only
  cluster-drain.sh srv-1-               # migrate from hosts matching 'srv-1-'
  cluster-drain.sh -a                   # migrate from current host, no prompts
  cluster-drain.sh -a -s                # simulate migration from current host 
  cluster-drain.sh --help               # show help
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

# remainder is ignore host (defaults to hostname -s)
if [[ ! -z "$1" ]]; then
    DRAIN_FROM="$1"
fi

# get list of all cluster nodes
# (except DRAIN_FROM provided)
ALL_NODES=($( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' | grep -v "$DRAIN_FROM" ))
NODE_INDEX=0

# make sure we have some target nodes
[ ${#ALL_NODES[@]} -eq 0 ] && fail "No valid migration targets!"
echo "Migration targets are ${ALL_NODES[@]}"

# make sure cluster is healthy
wait_for_healthy_cluster

for XML in /var/lib/virtual/conf/*.xml; do
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
  # don't migrate service, if not running on node we're trying to train
  echo "$ACTIVE_NODE" | grep -q "$DRAIN_FROM" 2>/dev/null
  [ $? -ne 0 ] && continue

  # round-robin all cluster nodes when migrating
  NEXT_NODE="${ALL_NODES[NODE_INDEX++ % ${#ALL_NODES[@]}]}"

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
