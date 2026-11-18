#!/bin/sh
set -eu

cd /shared
IFS= read -r container_id < /proc/sys/kernel/random/uuid
exec 9>>.lock

file_number=0
current_file=
stopping=0

create_file() {
    flock -x 9

    index=1
    while :; do
        case "$index" in
            ?)   candidate=00$index ;;
            ??)  candidate=0$index ;;
            *)   candidate=$index ;;
        esac
        if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
            break
        fi
        index=$((index + 1))
    done

    current_file=$candidate
    printf '%s\n%s\n' "$container_id" "$file_number" > "$current_file"
    flock -u 9
}

remove_file() {
    # Serialize deletion with allocation so an earlier name cannot
    # become free while another worker is scanning the sequence.
    flock -x 9
    removed_file=$current_file
    rm -f "$removed_file"
    current_file=
    flock -u 9
    printf '[%s] removed %s\n' "$container_id" "$removed_file"
}

cleanup() {
    if [ -n "$current_file" ]; then
        remove_file
    fi
}

trap 'stopping=1' HUP INT TERM
trap cleanup 0

while [ "$stopping" -eq 0 ]; do
    file_number=$((file_number + 1))
    create_file
    printf '[%s] created %s (file #%s)\n' "$container_id" "$current_file" "$file_number"
    [ "$stopping" -eq 0 ] || break
    sleep 1

    [ "$stopping" -eq 0 ] || break
    remove_file
    [ "$stopping" -eq 0 ] || break
    sleep 1
done
