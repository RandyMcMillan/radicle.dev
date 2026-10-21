#!/usr/bin/env bash
#
# clone-radicle-dev.sh - clone the repositories of the Radicle organization.
#
# By default the repositories are cloned from the Radicle network itself, the
# "sovereign forge": the script asks a public Radicle node (iris.radicle.network,
# run by the Radicle team) for the list of repositories and clones them over
# the node's git endpoint.
#
# Pass --github to clone the GitHub mirrors instead, i.e. every repository
# listed at https://github.com/orgs/radicle-dev/repositories.
#
# The clone is the upstream repository, so its "origin" remote is renamed to
# "upstream", leaving "origin" free for a fork.
#
# Usage:
#   scripts/clone-radicle-dev.sh [options] [destination]
#
# Options:
#   --github        Clone from the GitHub organization instead of the Radicle
#                   network. Every repository from
#                   https://github.com/orgs/radicle-dev/repositories is cloned,
#                   including archived and forked ones.
#   --node <url>    Radicle node to clone from (default: https://iris.radicle.network).
#   --dest <dir>    Destination directory for the clones (default: ./radicle-dev).
#   --depth <n>     Create shallow clones with the given depth (default: 1).
#                   Use 0 for the full history.
#   --only <name>   Only clone the given repository; may be passed multiple times.
#   --install-rad   Install the radicle binaries (rad, radicle-node and
#                   git-remote-rad) with https://radicle.dev/install, before
#                   cloning. Skipped if rad is already installed.
#   --force         Reinstall rad even if it is already installed. Requires
#                   --install-rad.
#   --dry-run       Show what would be cloned without cloning anything.
#   -h, --help      Show this help.
#
# Examples:
#   scripts/clone-radicle-dev.sh
#   scripts/clone-radicle-dev.sh --github
#   scripts/clone-radicle-dev.sh --github --dest ~/src/radicle-dev --depth 0
#   scripts/clone-radicle-dev.sh --install-rad
#   scripts/clone-radicle-dev.sh --install-rad --force

set -euo pipefail

ORG="radicle-dev"
DEFAULT_NODE="https://iris.radicle.network"
DEFAULT_DEST="radicle-dev"
DEFAULT_DEPTH="1"

node="$DEFAULT_NODE"
dest=""
depth="$DEFAULT_DEPTH"
source_github="false"
dry_run="false"
only=""
install_rad="false"
force="false"

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# Read a value for an option that requires one.
need_value() {
    [ "$2" -gt 0 ] || die "option $1 requires a value"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --github)
            source_github="true"
            ;;
        --node)
            need_value "$1" $(($# - 1))
            node="$2"
            shift
            ;;
        --dest)
            need_value "$1" $(($# - 1))
            dest="$2"
            shift
            ;;
        --depth)
            need_value "$1" $(($# - 1))
            depth="$2"
            shift
            ;;
        --only)
            need_value "$1" $(($# - 1))
            only="$only $2"
            shift
            ;;
        --dry-run)
            dry_run="true"
            ;;
        --install-rad)
            install_rad="true"
            ;;
        --force)
            force="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1 (try --help)"
            ;;
        *)
            break
            ;;
    esac
    shift
done

# A positional argument is the destination directory.
if [ $# -gt 0 ] && [ -z "$dest" ]; then
    dest="$1"
    shift
fi
[ $# -eq 0 ] || die "unexpected argument: $1"

[ -n "$dest" ] || dest="$DEFAULT_DEST"

case "$depth" in
    ''|*[!0-9]*) die "--depth expects a number, got: $depth" ;;
esac

if [ "$force" = "true" ] && [ "$install_rad" != "true" ]; then
    die "--force requires --install-rad"
fi

have git || die "git is required"

# Fetch a JSON document, failing with a readable message.
fetch_json() {
    local url="$1"
    local what="$2"
    local body

    if ! body=$(curl -fsSL -H "Accept: application/vnd.github+json" "$url"); then
        die "could not reach $what at $url"
    fi
    printf '%s' "$body"
}

# Repository names to clone, as "name<TAB>url" lines.
discover_github() {
    local page count body

    if have gh && gh auth status >/dev/null 2>&1; then
        gh api --paginate "orgs/${ORG}/repos?per_page=100" \
            --jq '.[] | [.name, .clone_url] | @tsv'
        return
    fi

    have curl || die "either the GitHub CLI (gh) or curl is required to list the repositories of ${ORG}"
    have jq || die "jq is required to list the repositories of ${ORG} (install the GitHub CLI (gh) instead)"

    page=1
    while :; do
        body=$(fetch_json "https://api.github.com/orgs/${ORG}/repos?per_page=100&page=${page}" "the GitHub API")
        count=$(printf '%s' "$body" | jq 'length')
        [ "$count" -gt 0 ] || break
        printf '%s' "$body" | jq -r '.[] | [.name, .clone_url] | @tsv'
        [ "$count" -eq 100 ] || break
        page=$((page + 1))
    done
}

discover_radicle() {
    have curl || die "curl is required to list the repositories of ${ORG}"
    have jq || die "jq is required to list the repositories of ${ORG}"

    fetch_json "${node}/api/v1/repos" "the Radicle node" |
        jq -r '.[] | [(.payloads["xyz.radicle.project"].data.name // .rid), .rid] | @tsv'
}

# The Radicle network serves git over http at https://<node>/<rid>.
radicle_url() {
    printf '%s/%s' "$node" "$1"
}

# Install the radicle binaries (rad, radicle-node and git-remote-rad) using
# the official installer, which downloads the signed release archive and
# installs it under $HOME/.radicle.
install_radicle() {
    local installer prefix

    if have rad; then
        if [ "$force" != "true" ]; then
            printf 'rad is already installed: %s\n' "$(rad --version 2>/dev/null | head -1)"
            return 0
        fi
        printf 'reinstalling rad (%s)\n' "$(rad --version 2>/dev/null | head -1)"
    fi

    # The installer installs into $RAD_HOME, defaulting to ~/.radicle.
    prefix="${RAD_HOME:-$HOME/.radicle}"

    have curl || die "curl is required to install rad"
    have tar || die "tar is required to install rad"
    have xz || die "xz is required to install rad"
    have ssh-keygen || die "ssh-keygen is required to install rad"

    installer=$(mktemp "${TMPDIR:-/tmp}/radicle-install.XXXXXX") ||
        die "could not create a temporary file"

    if ! curl -sSfL "https://radicle.dev/install" -o "$installer"; then
        rm -f "$installer"
        die "could not download the radicle installer"
    fi

    if ! sh "$installer"; then
        rm -f "$installer"
        die "the radicle installer failed"
    fi

    rm -f "$installer"

    printf 'installed rad: %s\n' "$("$prefix/bin/rad" --version 2>/dev/null | head -1)"
    printf 'add %s to your PATH to use it\n' "$prefix/bin"
}

if [ "$install_rad" = "true" ]; then
    if [ "$dry_run" = "true" ]; then
        if have rad; then
            if [ "$force" = "true" ]; then
                printf 'would reinstall the radicle binaries with https://radicle.dev/install\n'
            else
                printf 'rad is already installed: %s\n' "$(rad --version 2>/dev/null | head -1)"
            fi
        else
            printf 'would install the radicle binaries with https://radicle.dev/install\n'
        fi
    else
        install_radicle
    fi
    printf '\n'
fi

if [ "$source_github" = "true" ]; then
    echo "Cloning the repositories of ${ORG} from GitHub"
else
    echo "Cloning the repositories of ${ORG} from the Radicle network (${node})"
fi

repos=$(discover_github)
[ "$source_github" = "true" ] || repos=$(discover_radicle)

[ -n "$repos" ] || die "no repositories found for ${ORG}"

# Filter by --only, if given.
if [ -n "$only" ]; then
    filtered=""
    for name in $only; do
        found=$(printf '%s\n' "$repos" | awk -F'\t' -v n="$name" '$1 == n')
        [ -n "$found" ] || die "repository not found: ${name}"
        filtered="${filtered}${found}"$'\n'
    done
    repos="$filtered"
fi

if [ "$dry_run" != "true" ]; then
    mkdir -p "$dest"
fi

clone_args=""
if [ "$depth" -gt 0 ]; then
    clone_args="--depth ${depth}"
fi

total=0
cloned=0
skipped=0
failed=0

printf '\n'
while IFS=$'\t' read -r name url; do
    [ -n "$name" ] || continue
    total=$((total + 1))

    if [ "$source_github" != "true" ]; then
        url=$(radicle_url "$url")
    fi

    target="${dest}/${name}"

    if [ -e "$target" ]; then
        printf '  skip    %-28s %s\n' "$name" "$target"
        skipped=$((skipped + 1))
        continue
    fi

    if [ "$dry_run" = "true" ]; then
        printf '  clone   %-28s %s -> %s\n' "$name" "$url" "$target"
        cloned=$((cloned + 1))
        continue
    fi

    printf '  clone   %-28s %s\n' "$name" "$url"
    # shellcheck disable=SC2086 # clone_args is intentionally split into words
    if git clone $clone_args --quiet "$url" "$target"; then
        # The clone is the upstream repository, so name the remote accordingly
        # and leave "origin" free for a fork.
        if git -C "$target" remote rename origin upstream; then
            cloned=$((cloned + 1))
        else
            printf '  failed  %s (could not rename origin to upstream)\n' "$name" >&2
            failed=$((failed + 1))
        fi
    else
        printf '  failed  %s (%s)\n' "$name" "$url" >&2
        failed=$((failed + 1))
    fi
done < <(printf '%s\n' "$repos" | sed '/^$/d')

printf '\n'
if [ "$dry_run" = "true" ]; then
    printf '%d repositories would be cloned into %s\n' "$total" "$dest"
else
    printf '%d repositories: %d cloned, %d skipped, %d failed\n' "$total" "$cloned" "$skipped" "$failed"
fi

[ "$failed" -eq 0 ]
