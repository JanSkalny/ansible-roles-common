#!/bin/bash

# download new analyzers.json file
#XXX: curl https://download.thehive-project.org/analyzers.json > analyzers.json

echo "## docker pull"
for IMG in $( jq -r '.[] | .dockerImage' analyzers.json ); do
	echo "$IMG"
	docker pull "$IMG"
done

echo ""
echo "## prune old images"
docker image prune -f
