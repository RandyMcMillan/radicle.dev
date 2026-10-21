#!/usr/bin/env bash
#
# update-crates.sh - refresh the Cargo.toml dependency list from a crates.io
# search query.
#
# The crates.io search index matches on names, descriptions and keywords, so a
# query like "radicle" returns the whole radicle ecosystem *plus* crates from
# other projects that merely mention it. This script resolves each hit to a
# concrete, published version and writes them out as dependency entries.
#
# Requirements: curl, jq
#
set -euo pipefail

QUERY="radicle"
MANIFEST="Cargo.toml"
OUTPUT=""
DRY_RUN=0
PER_PAGE=100
EXCLUDE=()
LINUX_ONLY=()

# crates.io requires a User-Agent on every request.
USER_AGENT="radicle-dev-update-crates (https://github.com/radicle-dev)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Refresh Cargo.toml dependencies from a crates.io search query.

Options:
  -q, --query <query>    crates.io search query (default: "$QUERY")
  -m, --manifest <path>  Cargo.toml to update (default: "$MANIFEST")
  -o, --output <path>    write to <path> instead of updating the manifest
      --exclude <name>   skip a crate; repeatable
      --linux-only <name>
                          put a crate in the Linux target section; repeatable
      --dry-run          print the resolved dependencies, change nothing
  -h, --help             show this help

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --query radicle --exclude radicle-uri
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -q|--query)    QUERY="${2:?--query needs a value}"; shift 2 ;;
        -m|--manifest) MANIFEST="${2:?--manifest needs a value}"; shift 2 ;;
        -o|--output)   OUTPUT="${2:?--output needs a value}"; shift 2 ;;
        --exclude)
            EXCLUDE+=("${2:?--exclude needs a value}"); shift 2 ;;
        --linux-only)
            LINUX_ONLY+=("${2:?--linux-only needs a value}"); shift 2 ;;
        --dry-run)     DRY_RUN=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: $tool is required but not installed" >&2; exit 1
    }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- 1. collect every hit of the search -------------------------------------

api="https://crates.io/api/v1/crates?q=${QUERY}&per_page=${PER_PAGE}"

if ! curl -sS -f -A "$USER_AGENT" "$api&page=1" -o "$work/page1.json"; then
    echo "error: crates.io search request failed" >&2; exit 1
fi

total=$(jq -r '.meta.total // 0' "$work/page1.json")
pages=$(( (total + PER_PAGE - 1) / PER_PAGE ))
[ "$pages" -lt 1 ] && pages=1

: > "$work/all.json"
for page in $(seq 1 "$pages"); do
    if [ "$page" -eq 1 ]; then
        cp "$work/page1.json" "$work/p.json"
    elif ! curl -sS -f -A "$USER_AGENT" "$api&page=${page}" -o "$work/p.json"; then
        echo "error: crates.io search request failed on page $page" >&2; exit 1
    fi
    jq -c '.crates[]' "$work/p.json" >> "$work/all.json"
done

hits=$(wc -l < "$work/all.json" | tr -d ' ')
echo "crates.io search '$QUERY': $hits crates ($total reported)" >&2

# --- 2. resolve a usable version for every hit -------------------------------
#
# The search index reports a stale version for some crates, and a crate whose
# only published version has been yanked cannot be depended on at all. Both
# cases only need the extra versions lookup for the crates the search API
# already flags as yanked or without a stable release.

: > "$work/deps.txt"

while read -r name yanked stable; do
    [ -n "$name" ] || continue

    skip=0
    for ex in ${EXCLUDE[@]+"${EXCLUDE[@]}"}; do
        if [ "$name" = "$ex" ]; then
            echo "skipping $name (excluded)" >&2
            skip=1
            break
        fi
    done
    [ "$skip" -eq 0 ] || continue

    version=$(jq -s -r --arg n "$name" '
        .[] | select(.name == $n)
        | (.max_stable_version // .max_version // empty)
    ' "$work/all.json" | head -1)

    if [ -z "$version" ]; then
        echo "skipping $name (no version reported)" >&2
        continue
    fi

    if [ "$yanked" = "true" ] || [ "$stable" = "false" ]; then
        # Look for a version that actually exists and is not yanked.
        usable=""
        if curl -sS -f -A "$USER_AGENT" \
            "https://crates.io/api/v1/crates/${name}/versions" -o "$work/v.json"; then
            usable=$(jq -r --arg v "$version" '
                [.versions[] | select(.yanked == false)]
                | (map(select(.num == $v)) | first)
                // (sort_by(.created_at) | last)
                | .num // empty
            ' "$work/v.json")
        fi

        if [ -z "$usable" ]; then
            echo "skipping $name (every published version is yanked)" >&2
            continue
        fi
        if [ "$usable" != "$version" ]; then
            echo "note: $name resolved to $usable instead of $version" >&2
            version="$usable"
        fi
    fi

    printf '%s = "%s"\n' "$name" "$version" >> "$work/deps.txt"
done < <(jq -s -r '.[] | [.name, (.yanked|tostring), ((.max_stable_version != null)|tostring)] | @tsv' \
         "$work/all.json" | LC_ALL=C sort -u -k1,1)

resolved=$(wc -l < "$work/deps.txt" | tr -d ' ')
echo "resolved $resolved usable crates" >&2

# --- 3. write the dependencies out -------------------------------------------

# Crates that only build on Linux live in a target specific section.
: > "$work/linux.txt"
: > "$work/normal.txt"
while read -r entry; do
    name=${entry%% =*}
    for lo in ${LINUX_ONLY[@]+"${LINUX_ONLY[@]}"}; do
        if [ "$name" = "$lo" ]; then
            echo "$entry" >> "$work/linux.txt"
            continue 2
        fi
    done
    echo "$entry" >> "$work/normal.txt"
done < "$work/deps.txt"

if [ "$DRY_RUN" -eq 1 ]; then
    cat "$work/deps.txt"
    exit 0
fi

if [ -n "$OUTPUT" ]; then
    cp "$work/deps.txt" "$OUTPUT"
    echo "wrote $resolved dependencies to $OUTPUT" >&2
    exit 0
fi

# Replace the dependency entries of the [dependencies] and of the Linux target
# section, leaving every comment, blank line and other section untouched.
awk -v deps="$work/normal.txt" -v linuxdeps="$work/linux.txt" '
    function emit(file,   line) {
        while ((getline line < file) > 0) print line
    }
    function close_section() {
        if (sect == "deps" && !emitted) emit(deps)
        if (sect == "linux" && !emitted) emit(linuxdeps)
        sect = ""; emitted = 0
    }
    BEGIN { sect = ""; emitted = 0; seen_linux = 0 }
    /^[[:space:]]*\[/ {
        close_section()
        print
        if ($0 ~ /^[[:space:]]*\[dependencies\][[:space:]]*$/) sect = "deps"
        else if ($0 ~ /cfg\(target_os = "linux"\)/) { sect = "linux"; seen_linux = 1 }
        next
    }
    sect != "" {
        # keep comments and blank lines where they are
        if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) { print; next }
        # first dependency line of the section: emit the new list here
        if (!emitted) { emit(sect == "deps" ? deps : linuxdeps); emitted = 1 }
        next
    }
    { print }
    END {
        close_section()
        if (!seen_linux && (getline line < linuxdeps) > 0) {
            print ""
            print "[target.'"'"'cfg(target_os = \"linux\")'"'"'.dependencies]"
            print line
            while ((getline line < linuxdeps) > 0) print line
        }
    }
' "$MANIFEST" > "$work/manifest.new"

if cmp -s "$work/manifest.new" "$MANIFEST"; then
    echo "$MANIFEST already up to date" >&2
else
    cp "$work/manifest.new" "$MANIFEST"
    echo "updated $MANIFEST with $resolved dependencies" >&2
fi
