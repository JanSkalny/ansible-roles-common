#!/bin/bash

# get list of jobs from bconsole
JOBS=$( echo "show job" | bconsole | grep 'Job:.*Enabled=1' | grep -v 'level= ' | grep -v 'BackupCatalog' | awk '{print $2}' | sed 's/^name=//' )

# transform into JSON
jq -c -M -n --arg jobs "${JOBS}" '{ data: [ ( $jobs | split("\n") ) | .[] | { "{#JOB}": . } ] }'

