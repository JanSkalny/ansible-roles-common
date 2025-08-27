#!/bin/bash

# tunables
MIN_OBSERVE_TIME=10
MAX_OBSERVE_TIME=300
MAX_MIGRATE_TIME=300
AUTO_MIGRATE_TIME=5
WAIT_AFTER_MIGRATION=10

# cache crm conf show output
CRM_CONF="$(crm conf show)"

warn() {
  echo "$*" 1>&2
}

fail() {
  echo "$*" 1>&2
  exit 1
}

check_status() {
  CNT=$( crm status | grep -i "Pending Fencing Actions" | wc -l | awk '{print $1}' )
  [ $CNT -ne 0 ] && echo -n "S" && return 1

  CNT=$( crm status | grep -i "failed" | wc -l | awk '{print $1}' )
  [ $CNT -ne 0 ] && echo -n "f" && return 1

  CNT=$( crm status | grep "Migrating" | wc -l | awk '{print $1}' )
  [ $CNT -ne 0 ] && echo -n "m" && return 1

  CNT=$( crm status | grep "Monitoring" | wc -l | awk '{print $1}' )
  [ $CNT -ne 0 ] && echo -n "o" && return 1

  return 0
}

wait_for_healthy_cluster() {
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
}

cluster_vm_fqdn_from_xml() {
  [ -f "$XML" ] || fail "$1 file missing!"
  RES=$( cat "$1" | xmllint --xpath '/domain/metadata/fqdn/text()' - 2>/dev/null )
  [ "$RES" == "" ] && fail "$1 does not have a fqdn defined in its metadata!"
  echo "$RES"
}

cluster_vm_name_from_xml() {
  [ -f "$XML" ] || fail "$1 file missing!"
  RES=$( cat "$1" | xmllint --xpath '/domain/name/text()' - 2>/dev/null )
  [ "$RES" == "" ] && fail "$1 does not have name defined!"
  echo "$RES"
}

cluster_xml_from_vm_name() {
  RES=$( grep -l "<name>$1</name>" /var/lib/virtual/conf/*.xml 2>/dev/null )
  [ "$RES" == "" ] && fail "$1 does not have /var/lib/virtual/conf/ xml file!"
  [ "$(printf '%s\n' "$RES" | wc -l)" -ne 1 ] && fail "$1 is defined in more than one xml file!"
  echo "$RES"
}

cluster_vm_active_node() {
  crm status | grep "$1" | grep Started | rev | awk '{print $1}' | rev
}
