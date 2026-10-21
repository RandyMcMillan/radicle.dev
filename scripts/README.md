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
| `--dry-run` | Print the resolved dependencies, change nothing. |
| `-h`, `--help` | Show the help. |

The script replaces the dependency entries of the `[dependencies]` section and
of the Linux target section. Comments, blank lines and all other sections are
left untouched, so the notes next to the dependencies survive an update.

### Requirements

- `curl` and `jq`

### The radicle manifest

`Cargo.toml` in this repository holds every crate the `radicle` search returns
— 110 of them — minus the 16 that cannot be used together with the rest. They
are listed, commented out, at the end of the `[dependencies]` section together
with the reason each one is excluded. The Linux only crates live in
`[target.'cfg(target_os = "linux")'.dependencies]`.

The command that reproduces the current manifest:

```sh
scripts/update-crates.sh \
  --exclude radicle-ed25519-compact --exclude radicle-uri --exclude rad-uri \
  --exclude radicle-backup --exclude radicle-keystore --exclude gitorii \
  --exclude radicle-httpd --exclude git-commit --exclude radicle-feed \
  --exclude radicle-tui --exclude radicle-native-ci --exclude radicle-ci-adapter \
  --exclude radicle-ci-ambient --exclude radicle-ci-broker --exclude radicle-job \
  --exclude radicle-source \
  --linux-only syd \
  --linux-only rcp-tools-common --linux-only rcp-tools-filegen \
  --linux-only rcp-tools-rchm --linux-only rcp-tools-rcmp --linux-only rcp-tools-rcp \
  --linux-only rcp-tools-remote --linux-only rcp-tools-rlink --linux-only rcp-tools-rrm
```

Excluded crates fall into three groups:

- **Version conflicts** — the crate cannot be resolved next to the others, for
  example `radicle-uri` pins `cyphergraphy =0.3.0` while `radicle` needs
  `^0.3.1`, and `radicle-backup` and `radicle-keystore` need two different
  `sqlite3`/`zeroize` versions.
- **Unbuildable code** — the crate resolves but does not compile next to the
  others, for example `radicle-native-ci` pulls `radicle 0.22`, whose
  `radicle-crypto 0.16` predates the `Display` bound that `cyphergraphy 0.3.1`
  added.
- **Yanked releases** — `radicle-ed25519-compact` only ever published version
  has been yanked, so it cannot be depended on at all.
