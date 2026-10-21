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
OPTIONAL=()

# crates.io requires a User-Agent on every request.
USER_AGENT="radicle-dev-update-crates (https://github.com/radicle-dev)"

# The script only rewrites the block between these markers. The package has
# dependencies of its own next to the ones coming from the search, and those
# have to survive an update.
START_MARKER="# >>> crates.io search results >>>"
END_MARKER="# <<< crates.io search results <<<"

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
      --optional <name>
                          feature guard a crate; repeatable. The crate is
                          written as an optional dependency and gets a feature
                          of the same name that enables it.
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
        --optional)
            OPTIONAL+=("${2:?--optional needs a value}"); shift 2 ;;
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

# Crates that only build on Linux live in a target specific section, crates
# that do not compile next to the others are feature guarded.
: > "$work/linux.txt"
: > "$work/features.list"
: > "$work/features.txt"
: > "$work/deps.list"
while read -r entry; do
    name=${entry%% =*}
    version=${entry#*= }
    version=${version#\"}
    version=${version%\"}

    for lo in ${LINUX_ONLY[@]+"${LINUX_ONLY[@]}"}; do
        if [ "$name" = "$lo" ]; then
            echo "$entry" >> "$work/linux.txt"
            continue 2
        fi
    done

    for op in ${OPTIONAL[@]+"${OPTIONAL[@]}"}; do
        if [ "$name" = "$op" ]; then
            echo "$name = { version = \"$version\", optional = true }" >> "$work/deps.list"
            echo "$name = [\"dep:$name\"]" >> "$work/features.list"
            continue 2
        fi
    done

    echo "$entry" >> "$work/deps.list"
done < "$work/deps.txt"

LC_ALL=C sort -o "$work/deps.list" "$work/deps.list"
LC_ALL=C sort -o "$work/linux.txt" "$work/linux.txt"
LC_ALL=C sort -o "$work/features.list" "$work/features.list"

{
    echo "default = []"
    cat "$work/features.list"
} > "$work/features.txt"

if [ "$DRY_RUN" -eq 1 ]; then
    cat "$work/deps.txt"
    exit 0
fi

if [ -n "$OUTPUT" ]; then
    cp "$work/deps.txt" "$OUTPUT"
    echo "wrote $resolved dependencies to $OUTPUT" >&2
    exit 0
fi

# Replace the block of search results in the [dependencies] section, the
# entries of the [features] section and of the Linux target section. Every
# comment, blank line and other section is left untouched.
awk -v deps="$work/deps.list" -v linuxdeps="$work/linux.txt" -v features="$work/features.txt" \
    -v start="$START_MARKER" -v end="$END_MARKER" -v srcurl="https://crates.io/search?q=${QUERY}" '
    function emit(file,   line) {
        while ((getline line < file) > 0) print line
    }
    function emit_block() {
        print start
        print "# " srcurl " - generated by scripts/update-crates.sh, do not edit by hand"
        emit(deps)
        print end
    }
    function close_section() {
        if (sect == "deps" && !emitted && !seen_block) emit(deps)
        if (sect == "linux" && !emitted) emit(linuxdeps)
        if (sect == "features" && !emitted) emit(features)
        sect = ""; emitted = 0; in_block = 0
    }
    BEGIN {
        sect = ""; emitted = 0; seen_linux = 0; seen_features = 0
        in_block = 0; seen_block = 0
        # the crates of the search, so that the other entries of the section
        # can be told apart from them
        while ((getline line < deps) > 0) {
            if (match(line, /^[a-zA-Z0-9_-]+/)) managed[substr(line, 1, RLENGTH)] = 1
        }
        close(deps)
    }
    /^[[:space:]]*\[/ {
        close_section()
        print
        if ($0 ~ /^[[:space:]]*\[dependencies\][[:space:]]*$/) sect = "deps"
        else if ($0 ~ /^[[:space:]]*\[features\][[:space:]]*$/) { sect = "features"; seen_features = 1 }
        else if ($0 ~ /cfg\(target_os = "linux"\)/) { sect = "linux"; seen_linux = 1 }
        next
    }
    sect == "deps" {
        # the block between the markers is generated, everything else is ours
        if (!in_block && $0 == start) { in_block = 1; seen_block = 1; emit_block(); next }
        if (in_block) { if ($0 == end) in_block = 0; next }
        if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) { print; next }
        # a manifest without the markers: the entries of the search are
        # replaced, the ones the script does not know about are kept
        if (match($0, /^[a-zA-Z0-9_-]+/) && substr($0, 1, RLENGTH) in managed) {
            if (!emitted) { emit(deps); emitted = 1 }
            next
        }
        print
        next
    }
    sect != "" {
        # keep comments and blank lines where they are
        if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) { print; next }
        # first entry of the section: emit the new list here
        if (!emitted) {
            if (sect == "linux") emit(linuxdeps)
            else emit(features)
            emitted = 1
        }
        next
    }
    { print }
    END {
        close_section()
        if (!seen_features) {
            print ""
            print "[features]"
            while ((getline line < features) > 0) print line
        }
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
