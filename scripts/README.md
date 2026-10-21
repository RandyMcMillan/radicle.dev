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
