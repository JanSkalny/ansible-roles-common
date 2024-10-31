#!/bin/bash

# tunables
MIN_OBSERVE_TIME=3		#XXX: 10
MAX_OBSERVE_TIME=300
MAX_MIGRATE_TIME=300
AUTO_MIGRATE_TIME=5
WAIT_AFTER_MIGRATION=10

warn() {
	echo "$*" 1>&2
}

fail() {
	echo "$*" 1>&2
	exit 1
}

check_status() {
	CNT=$( crm status | grep -i "failed" | wc -l | awk '{print $1}' )
	[ $CNT -ne 0 ] && echo -n "f" && return 1

	CNT=$( crm status | grep "Migrating" | wc -l | awk '{print $1}' )
	[ $CNT -ne 0 ] && echo -n "m" && return 1

	CNT=$( crm status | grep "Monitoring" | wc -l | awk '{print $1}' )
	[ $CNT -ne 0 ] && echo -n "o" && return 1

	return 0
}

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

# get list of all cluster nodes except ariber
NODES=($( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' | grep -v arbiter ))
NODE_INDEX=0

# make sure we have some target nodes
[ ${#NODES[@]} -eq 0 ] && fail "No valid migration targets!"

for GROUP in $( grep service_group /var/lib/virtual/conf/*.xml | cut -d '>' -f 2 | cut -d '<' -f 1 | sort | uniq ); do

	FIRST_NODE=""
	echo "Solving service group $GROUP..."

	for XML_FILE in $( grep "<service_group>$GROUP</service_group>" /var/lib/virtual/conf/*.xml -l ); do

		# make sure cluster is healthy
		echo -n "Checking cluster status..."
		FAILS=$MIN_OBSERVE_TIME
		ATTEMPTS=0
		while [[ $FAILS -gt 0 ]]; do
			((ATTEMPTS++))
			((FAILS--))

			sleep 1 
			check_status
			if [[ $? -eq 1 ]]; then
				# failure resets count-down to 10
				FAILS=$MIN_OBSERVE_TIME
			else
				echo -n "."
			fi

			# terminate after 300 seconds
			[[ $ATTEMPTS -ge $MAX_OBSERVE_TIME ]] && fail " UNCLEAN!"
		done
		echo " OK"


		# figure out vm name and uuid
		NAME=$(cat "$XML_FILE" | xmllint --xpath '/domain/metadata/fqdn/text()' - 2>/dev/null)
		[ -z "$NAME" ] && fail "$VM does not have a fqdn defined in its metadata!"

		#XXX: fixme for short uuids
		UUID=$( cat "$XML_FILE" | xmllint --xpath 'string(/domain/uuid/text())' - | cut -d '-' -f 1)
		VM="vm-${UUID}"

		ACTIVE_NODE=$( crm status | grep "$VM" | grep Started | rev | awk '{print $1}' | rev )

		if [ "$ACTIVE_NODE" == "" ]; then
			warn "VM not running! ($VM)"
			continue
		fi

		echo "Group member $NAME ($VM) running on $ACTIVE_NODE"

		if [ "$FIRST_NODE" == "" ]; then
			FIRST_NODE="$ACTIVE_NODE"
			NODES=($( crm status | grep -oP 'Online: \[\K[^\]]+' | tr ', ' '\n' | grep -v '^$' | grep -v arbiter | grep -v "$ACTIVE_NODE" ))
			echo "Leave member running on $FIRST_NODE"
			echo "Migration targets are ${NODES[@]}"
			continue
		fi

		if [ "$FIRST_NODE" == "$ACTIVE_NODE" ]; then
			NEXT_NODE="${NODES[NODE_INDEX++ % ${#NODES[@]}]}"
			echo "Migration required to $NEXT_NODE"
		fi

		if [[ "$ASK_FOR_CONFIRMATION" == true ]]; then
			# confirm migration
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
			echo "Simulated crm res move ${VM}_vm $NEXT_NODE"
			sleep 1
		else
			# request migration
			crm res move "${VM}_vm" $NEXT_NODE > /dev/null

			# observe migration process
			for I in $( seq 1 $MAX_MIGRATE_TIME ); do
				sleep 1
				STATUS=$( virsh list | grep $VM | awk '{print $3}')
				virsh list | grep $VM > /dev/null

				# stop waiting
				if [ $? -eq 1 ]; then
					echo " migrated!"
					echo ""
					sleep $WAIT_AFTER_MIGRATION
					break
				fi
				echo -n "${STATUS:0:1}"
			done
		fi
	done
	echo ""
done
