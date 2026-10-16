{% raw %}
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

DIR=/var/backups/docker
mkdir -p "$DIR"/{containers,images}

docker ps --no-trunc >"$DIR/ps.txt"
docker image ls -a --no-trunc \
    --format '{{.ID}}\t{{.Repository}}:{{.Tag}}' >"$DIR/images.txt"

rm -f -- "$DIR"/containers/*.inspect
declare -A KEEP=()

containers=$(docker ps -q --no-trunc)

while IFS= read -r container; do
    [[ -n $container ]] || continue

    inspect="$DIR/containers/$container.inspect"
    docker inspect "$container" >"$inspect"

    image=$(jq -er '.[0].Image' "$inspect")
    KEEP["$image"]=1
    archive="$DIR/images/$image.tar"

    if [[ ! -f $archive ]]; then
        echo "Saving $image"
        docker image save -o "$archive" "$image" ||
            { rm -f -- "$archive"; exit 1; }
    fi
done <<<"$containers"

for archive in "$DIR"/images/*.tar; do
    image=${archive##*/}
    image=${image%.tar}

    if [[ ! ${KEEP[$image]+yes} ]]; then
        echo "Pruning $image"
        rm -f -- "$archive"
    fi
done
{% endraw %}
