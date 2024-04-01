#!/bin/bash

fail() {
  echo "$*" 1>&2
  exit 1
}

[[ "x$CORTEX_URL" -eq "x" ]] && fail "$0: missing CORTEX_URL"

[ -f analyzers.json ] || fail "missing analyzers.json"

# list enabled analyzers
echo "## active analyzers"
curl -s -k -H "Authorization: Bearer $CORTEX_TOKEN" "$CORTEX_URL/api/analyzer" | jq -r -c '.[] | {name,version}' 

# iterate over names without versions
echo "## analyzers from analyzers.json"
for NAME in $( curl -s -k -H "Authorization: Bearer $CORTEX_TOKEN" "$CORTEX_URL/api/analyzer" | jq -r -c '.[] | .name' | sed 's/[_0-9]*$//' ); do
  jq -rc '.[]|{name,version}' analyzers.json | grep "\"$NAME\"" | jq -c
done

