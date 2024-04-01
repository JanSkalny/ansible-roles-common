#!/bin/bash

fail() {
  echo "$*" 1>&2
  exit 1
}

[[ "x$CORTEX_URL" -eq "x" ]] && fail "$0: missing CORTEX_URL"

[ -f analyzers.json ] || fail "missing analyzers.json"

# list enabled analyzers
echo "## active analyzers"
curl -s -k -H "Authorization: Bearer $CORTEX_TOKEN" "$CORTEX_URL/api/analyzer?range=all" | jq -r -c '.[] | {name,version}'  > analyzers-server.json

# iterate over names without versions
echo "## analyzers from analyzers.json"
for NAME in $( jq -rc '.name' analyzers-server.json | sed 's/[_0-9]*$//' ); do
  VER1=$( jq -rc '.[] | select(.name == "'$NAME'") | .version' analyzers.json )
  VER2=$( grep "\"$NAME[_0-9]*\"" analyzers-server.json | jq -rc '.version' )
  if [ "$VER1" != "$VER2" ]; then
    echo "version mismatch $NAME"
    echo "- definiton: $VER1"
    echo "- server: $VER2"
  fi
done


