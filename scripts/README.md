# Scripts

## `clone-radicle-dev.sh`

Clones the repositories of the [Radicle](https://radicle.dev) organization.

By default the repositories are cloned from the Radicle network itself, the
"sovereign forge": the script asks a public Radicle node
([iris.radicle.network](https://radicle.network/nodes/iris.radicle.network),
run by the Radicle team) for the list of repositories and clones them over the
node's git endpoint.

Pass `--github` to clone the GitHub mirrors instead, i.e. every repository
listed at <https://github.com/orgs/radicle-dev/repositories>.

### Usage

```
scripts/clone-radicle-dev.sh [options] [destination]
```

| Option | Description |
| --- | --- |
| `--github` | Clone from the GitHub organization instead of the Radicle network. Every repository from <https://github.com/orgs/radicle-dev/repositories> is cloned, including archived and forked ones. |
| `--node <url>` | Radicle node to clone from (default: `https://iris.radicle.network`). |
| `--dest <dir>` | Destination directory for the clones (default: `./radicle-dev`). |
| `--depth <n>` | Create shallow clones with the given depth (default: `1`). Use `0` for the full history. |
| `--only <name>` | Only clone the given repository; may be passed multiple times. |
| `--install-rad` | Install the radicle binaries (`rad`, `radicle-node` and `git-remote-rad`) with <https://radicle.dev/install> before cloning. Skipped if `rad` is already installed. |
| `--force` | Reinstall rad even if it is already installed. Requires `--install-rad`. |
| `--dry-run` | Show what would be cloned without cloning anything. |
| `-h`, `--help` | Show the help. |

### Examples

```sh
# Clone the organization's repositories from the Radicle network
scripts/clone-radicle-dev.sh

# Clone all repositories from the GitHub organization
scripts/clone-radicle-dev.sh --github

# Install the radicle CLI first, then clone
scripts/clone-radicle-dev.sh --install-rad

# Reinstall (upgrade) the radicle CLI, then clone
scripts/clone-radicle-dev.sh --install-rad --force

# Clone a couple of repositories with their full history
scripts/clone-radicle-dev.sh --github --only heartwood --only radicle-tui --depth 0

# See what would be cloned
scripts/clone-radicle-dev.sh --github --dry-run
```

### Requirements

- `git`
- `curl` and `jq`, or the [GitHub CLI](https://cli.github.com) (`gh`) — `gh` is
  used when it is available and authenticated, otherwise the GitHub API is
  queried directly.
- `tar`, `xz` and `ssh-keygen`, only for `--install-rad`.

Existing directories are never touched; a repository that has already been
cloned is skipped.

The cloned repository is the upstream one, so its `origin` remote is renamed to
`upstream` right after the clone. This leaves `origin` free to be pointed at a
fork:

```sh
cd radicle-dev/heartwood
git remote add origin git@github.com:<you>/heartwood.git
git push -u origin main
```

## `update-crates.sh`

Refreshes the dependency list in `Cargo.toml` from a [crates.io](https://crates.io)
search query.

The crates.io search index matches on names, descriptions and keywords, so a
query like `radicle` returns the whole radicle ecosystem *plus* crates from
other projects that merely mention it. The script resolves every hit to a
concrete, published version and writes them out as dependency entries.

### Usage

```
scripts/update-crates.sh [options]
```

| Option | Description |
| --- | --- |
| `--query <query>` | crates.io search query (default: `radicle`). |
| `--manifest <path>` | `Cargo.toml` to update (default: `Cargo.toml`). |
| `--output <path>` | Write to `<path>` instead of updating the manifest. |
| `--exclude <name>` | Skip a crate; may be passed multiple times. |
| `--linux-only <name>` | Put a crate in the Linux target section; may be passed multiple times. |
| `--optional <name>` | Feature guard a crate; may be passed multiple times. The crate is written as an optional dependency and gets a feature of the same name that turns it on. |
| `--dry-run` | Print the resolved dependencies, change nothing. |
| `-h`, `--help` | Show the help. |

The script rewrites the block of search results in the `[dependencies]`
section, the entries of the `[features]` section and of the Linux target
section. The block is delimited by two markers:

```toml
# >>> crates.io search results >>>
# <<< crates.io search results <<<
```

Everything outside the markers is left untouched, so the dependencies of this
package itself, the notes next to the dependencies and all other sections
survive an update.

### Requirements

- `curl` and `jq`

### The radicle manifest

`Cargo.toml` in this repository holds every crate the `radicle` search returns
— 110 of them — next to the dependencies of this package itself:

| | Crates | Where |
| --- | --- | --- |
| Plain dependencies | 85 | the search results block of `[dependencies]` |
| Feature guarded | 6 | the search results block, as optional dependencies |
| Linux only | 9 | `[target.'cfg(target_os = "linux")'.dependencies]` |
| Excluded | 10 | commented out after the search results block |

The command that reproduces the current manifest is in `crates-flags`, next to this file. It is the single source of truth: the justfile, the CI job and this page all read it.

```sh
scripts/update-crates.sh $(grep -v '^[[:space:]]*#' scripts/crates-flags | tr '\n' ' ')
```

The flags it holds:

| Flag | Crates |
| --- | --- |
| `--exclude <name>` | 10 crates that cannot be resolved next to the rest |
| `--optional <name>` | 6 crates that resolve but do not compile, so they are feature guarded |
| `--linux-only <name>` | 9 crates that only build on Linux |

The same command runs in CI: `.github/workflows/gnostr-dev.yml` refreshes the
manifest every night and fails when the result differs from the committed
`Cargo.toml`. That is the signal to run the command above and commit what it
writes.

### Feature guards

Six crates resolve but do not compile next to the rest of the tree. They are
written as optional dependencies, so `cargo check` stays green and the crate is
only built when its feature is turned on:

```toml
[features]
radicle-source = ["dep:radicle-source"]
```

Turning a feature on pulls in the broken code, so `cargo check --features
radicle-source` fails to compile — that is the point of the guard, it keeps the
rest of the tree buildable while the crate stays available.

### Excluded crates

The ten excluded crates cannot be feature guarded. Cargo resolves optional
dependencies as well, so they break `cargo generate-lockfile` even when their
feature is turned off. They fall into two groups:

- **Version conflicts** — the crate cannot be resolved next to the others, for
  example `radicle-uri` pins `cyphergraphy =0.3.0` while `radicle` needs
  `^0.3.1`, and `radicle-backup` and `radicle-keystore` need two different
  `sqlite3`/`zeroize` versions.
- **Yanked releases** — `radicle-ed25519-compact` only ever published version
  has been yanked, so it cannot be depended on at all.
