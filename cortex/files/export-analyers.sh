#!/bin/bash

fail() {
  echo "$*" 1>&2
  exit 1
}

[[ "x$CORTEX_URL" -eq "x" ]] && fail "$0: missing CORTEX_URL"

# list enabled analyzers
curl -k -H "Authorization: Bearer $CORTEX_TOKEN" "$CORTEX_URL/api/analyzer" | jq '{cortex_analyers: [.[] | {name,configuration}]}' | yq -P

