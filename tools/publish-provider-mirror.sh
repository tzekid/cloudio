#!/bin/sh
set -eu

name=${1:-}
repository=${2:-}
case "$name" in
    cloudflare|hostinger) ;;
    *)
        printf '%s\n' "usage: $0 cloudflare|hostinger owner/repository" >&2
        exit 2
        ;;
esac
if [ -z "$repository" ]; then
    printf '%s\n' "missing mirror repository" >&2
    exit 2
fi

test -n "${MIRROR_SSH_KEY:-}"
test -d "packages/$name"
test -z "$(git status --porcelain --untracked-files=no)"

mirror_tmp=$(mktemp -d)
trap 'rm -rf "$mirror_tmp"' EXIT HUP INT TERM
key_path="$mirror_tmp/id_ed25519"
known_hosts="$mirror_tmp/known_hosts"
printf '%s\n' "$MIRROR_SSH_KEY" >"$key_path"
chmod 600 "$key_path"
ssh-keyscan -t ed25519 github.com >"$known_hosts" 2>/dev/null

split_commit=$(git subtree split --prefix "packages/$name" master)
GIT_SSH_COMMAND="ssh -i $key_path -o IdentitiesOnly=yes -o UserKnownHostsFile=$known_hosts" \
    git push "git@github.com:$repository.git" "$split_commit:refs/heads/master"
