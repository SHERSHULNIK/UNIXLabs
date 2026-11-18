#!/bin/sh
set -eu

count=${1:-}
if [ "$#" -gt 1 ]; then
    printf 'Usage: sh build.sh [1|10|50]\n' >&2
    exit 2
fi
case "$count" in
    ''|1|10|50) ;;
    *)
        printf 'Usage: sh build.sh [1|10|50]\n' >&2
        exit 2
        ;;
esac

cd "$(dirname "$0")"
image=unix-concurrent
volume=unix-concurrent-files
mount="type=volume,source=$volume,target=/shared"

docker build -t "$image" .
docker volume create "$volume"

[ -n "$count" ] || exit 0

stop_containers() {
    if [ "$#" -gt 0 ]; then
        docker stop "$@" >/dev/null
    fi
}

set --
trap 'stop_containers "$@"' 0
trap 'exit 130' INT
trap 'exit 143' TERM

while [ "$#" -lt "$count" ]; do
    # Keep the Linux mount path intact when Docker is called from Git Bash.
    container_id=$(MSYS_NO_PATHCONV=1 docker run -d --rm --mount "$mount" "$image")
    set -- "$@" "$container_id"
done

printf 'Started %s container(s).\n' "$#"
sleep 5
MSYS_NO_PATHCONV=1 docker exec "$1" ls -la /shared
docker logs --tail 8 "$1"
