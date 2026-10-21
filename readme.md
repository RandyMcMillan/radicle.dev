<div align="center">

# gnostr-dev

**Clone and sync every Git repository you can access, on every provider, with one command.**

[![CI](https://github.com/RandyMcMillan/radicle.dev/actions/workflows/gnostr-dev.yml/badge.svg)](https://github.com/RandyMcMillan/radicle.dev/actions/workflows/gnostr-dev.yml)
[![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20macOS%20%7C%20Windows-informational)](#installation)
[![License](https://img.shields.io/github/license/RandyMcMillan/radicle.dev)](LICENSE)

[Repository](https://github.com/RandyMcMillan/radicle.dev) · [Upstream project](https://github.com/Dxsk/repos-manager) · [Documentation](https://repos-manager.dxscloud.fr)

</div>

---

> **gnostr-dev** is a build of the upstream project
> [repos-manager](https://github.com/Dxsk/repos-manager), under a new name. The
> providers, the configuration and the behaviour are the upstream ones. What
> changed is the name of the command, of the config directory, of the
> environment variables and of the releases. The upstream releases are published
> under the name `repos-manager`; they are not the releases of this tool.

If your code is spread over GitHub, a GitLab group, a self-hosted Forgejo and a couple of Bitbucket workspaces, keeping a local copy of everything up to date is tedious. `gnostr-dev` asks each provider for every repository you can access (personal, collaborations, organizations, groups and subgroups) and mirrors them into `<base_dir>/<host>/<owner>/<repo>`, cloning what is missing and fast-forwarding the rest.

It is a single native binary for Linux, macOS and Windows. At runtime it only needs `git` and the official CLI of each provider you sync.

```console
$ gnostr-dev sync --all
$ gnostr-dev status
  github.com/Dxsk/git-identity-manager dirty
  github.com/Dxsk/mtd ahead (+2)
  gitlab.com/work/api behind (-3)

Total: 42 repos - 39 clean, 1 dirty, 1 ahead, 1 behind, 0 diverged
```

## Supported providers

| Provider | CLI | Notes |
|---|---|---|
| GitHub | [`gh`](https://cli.github.com/) | github.com and GitHub Enterprise |
| GitLab | [`glab`](https://gitlab.com/gitlab-org/cli) | Groups and nested subgroups |
| Forgejo / Gitea / Gogs | [`tea`](https://gitea.com/gitea/tea) | Optional: `tea` is used for login only, and `gnostr-dev forgejo login` can store a token instead |
| Bitbucket | [`bitbucket`](https://crates.io/crates/bitbucket-cli) | Optional. Cloud with an Atlassian API token, Data Center with an HTTP access token |
| Sourcehut | [`hut`](https://sr.ht/~xenrox/hut) | Names keep their tilde: `~user/repo` |
| OneDev | none | Self-hosted, an access token saved by `gnostr-dev onedev login` |
| Radicle | [`rad`](https://radicle.xyz/guides/user) | |
| Plain git server | none | Any server with no API: URLs from the config, or listed over SSH (gitolite, Soft Serve) |

**Not every provider is equally proven.** GitHub, GitLab, Forgejo and the config URLs of the plain git server are **stable**: their listing has been run against the live API, offline tests cover the parsing.

Six surfaces are **alpha**: Bitbucket Cloud, Bitbucket Data Center, Radicle, Sourcehut, OneDev, and the SSH discovery modes of the plain git server (`gitolite`, `soft-serve`, `find:<root>`). They are implemented against the published API documentation and covered by offline tests only, and no live server of that kind has ever answered a request from `gnostr-dev`. They may work on the first try, or list nothing. If one misbehaves, an issue with the raw payload the server returned and the server version is what makes a fix possible, and it becomes a test fixture. Per provider detail in the [provider reference](https://repos-manager.dxscloud.fr/docs/providers/#provider-status).

## Installation

<details open>
<summary><b>From this repository</b></summary>

<br>

You need a stable [Rust toolchain](https://rustup.rs). `make` or `just` builds the tool and installs the command:

```sh
git clone https://github.com/RandyMcMillan/radicle.dev.git
cd radicle.dev
make install                    # builds and installs to ~/.local/bin/gnostr-dev
make install PREFIX=/usr/local  # or anywhere else
make completions                # bash, zsh and fish completions in your user directories
make uninstall
```

The justfile does the same, with the recipes of the repository:

```sh
just install
just completions
```

Packagers can stage the install with `DESTDIR`. Cargo works too, straight from the repository:

```sh
cargo install --path .
```

</details>

<details>
<summary><b>Upstream releases</b></summary>

<br>

The upstream project publishes prebuilt binaries for every platform on its [GitHub releases page](https://github.com/Dxsk/repos-manager/releases), which has every platform. The [Forgejo releases](https://forge.infrasouveraine.fr/dxsk/repos-manager/releases) carry the Linux and Windows x86_64 builds. They are built from the upstream source, so they install a command called `repos-manager`, not `gnostr-dev`.

<details open>
<summary><b>Package managers</b></summary>

<br>

| Where | Package | Command |
|---|---|---|
| [crates.io](https://crates.io/crates/repos-manager) | `repos-manager` | `cargo install repos-manager` |
| [AUR](https://aur.archlinux.org/packages/repos-manager-bin) (Arch, Manjaro, CachyOS...) | `repos-manager-bin` (prebuilt) | `yay -S repos-manager-bin` |
| [AUR](https://aur.archlinux.org/packages/repos-manager) | `repos-manager` (built from source) | `yay -S repos-manager` |

The AUR packages also install the bash, zsh and fish completions. Update these installs through the package manager: `repos-manager update` detects them and tells you which command to run instead of replacing the binary.

</details>

<details open>
<summary><b>Linux and macOS</b></summary>

<br>

```sh
curl -fsSL https://raw.githubusercontent.com/Dxsk/repos-manager/main/installers/install.sh | sh
```

The script downloads the archive that matches your OS and CPU, checks it against the release's `SHA256SUMS`, and puts the binary in `~/.local/bin`. Options go after `sh -s --`, and most of them also have an environment variable:

| Option | Variable | Default | |
|---|---|---|---|
| `--version vX.Y.Z` | `REPOS_MANAGER_VERSION` | latest | Release to install |
| `--prefix DIR` | `PREFIX` | `~/.local` | Installs into `DIR/bin` |
| `--source github\|forge` | | `github` | Where to download from |
| `--uninstall` | | | Removes the installed binary |

```sh
# Pin a version, system-wide
curl -fsSL https://raw.githubusercontent.com/Dxsk/repos-manager/main/installers/install.sh | sudo sh -s -- --version v1.0.0 --prefix /usr/local

# Download from the forge instead of GitHub (Linux only, macOS builds are on GitHub)
curl -fsSL https://forge.infrasouveraine.fr/dxsk/repos-manager/raw/branch/main/installers/install.sh | sh -s -- --source forge

# Uninstall
curl -fsSL https://raw.githubusercontent.com/Dxsk/repos-manager/main/installers/install.sh | sh -s -- --uninstall
```

</details>

<details open>
<summary><b>Windows</b></summary>

<br>

With PowerShell:

```powershell
irm https://raw.githubusercontent.com/Dxsk/repos-manager/main/installers/install.ps1 | iex
```

It installs `repos-manager.exe` into `%LOCALAPPDATA%\Programs\repos-manager` and adds that folder to your user `PATH`. Open a new terminal afterwards.

The script accepts `-Version`, `-Source github|forge`, `-InstallDir` and `-Uninstall`. To pass them without saving the file first:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Dxsk/repos-manager/main/installers/install.ps1))) -Version v1.0.0
```

Setting `$env:REPOS_MANAGER_VERSION = "v1.0.0"` before the one-liner pins a version too.

Prefer an installer? Download and run `repos-manager-x86_64-setup.exe` (or `repos-manager-aarch64-setup.exe` on ARM devices). It installs per user, so it does not ask for admin rights, adds the program to your `PATH` and shows up in *Apps & features* if you want to remove it later. For a silent install, pass `/S`:

```powershell
.\repos-manager-x86_64-setup.exe /S
```

If you would rather not install anything, grab the portable `.zip` and put `repos-manager.exe` somewhere on your `PATH`.

</details>

<details>
<summary><b>Release assets</b></summary>

<br>

Assets are named after the Rust target they were built for:

| Asset | Platform | GitHub | Forgejo |
|---|---|:---:|:---:|
| `repos-manager-x86_64-unknown-linux-musl.tar.gz` | Linux x86_64 (static) | ✓ | ✓ |
| `repos-manager-aarch64-unknown-linux-musl.tar.gz` | Linux aarch64 (static) | ✓ | ✓ |
| `repos-manager-x86_64-apple-darwin.tar.gz` | macOS Intel | ✓ | |
| `repos-manager-aarch64-apple-darwin.tar.gz` | macOS Apple Silicon | ✓ | |
| `repos-manager-x86_64-pc-windows-msvc.zip` | Windows x86_64 | ✓ | |
| `repos-manager-aarch64-pc-windows-msvc.zip` | Windows ARM64 | ✓ | |
| `repos-manager-x86_64-pc-windows-gnu.zip` | Windows x86_64 (MinGW build) | | ✓ |
| `repos-manager-x86_64-setup.exe` | Windows x86_64 installer | ✓ | ✓ |
| `repos-manager-aarch64-setup.exe` | Windows ARM64 installer | ✓ | |

</details>

<details>
<summary><b>Verifying a download</b></summary>

<br>

Every release ships two checksum files:

- `SHA256SUMS` lists the archives and installers you download.
- `SHA256SUMS-binaries` lists the `repos-manager` binary inside each archive. Use it to check a binary you already extracted or installed.

On Linux and macOS:

```sh
sha256sum --ignore-missing -c SHA256SUMS   # macOS: shasum -a 256 --ignore-missing -c SHA256SUMS
```

On Windows:

```powershell
(Get-FileHash .\repos-manager-x86_64-setup.exe).Hash.ToLower()
(Get-FileHash "$env:LOCALAPPDATA\Programs\repos-manager\repos-manager.exe").Hash.ToLower()
```

Then compare the result with the matching line in the checksum file. The install scripts and `repos-manager update` do this for you.

</details>

</details>

### Requirements

- `git`
- The CLI of each provider you sync: `gh`, `glab`, `tea`, `hut`, `bitbucket` (optional) or `rad`
- `ssh`, to sync a plain git server that lists itself

OneDev and plain git servers need no extra CLI at all.

Nothing else: no `bash`, `jq`, `yq` or `curl` needed at runtime.

## Getting started

```sh
gnostr-dev init         # optional, writes ~/.config/gnostr-dev/config.json
gnostr-dev login        # authenticates every provider whose CLI is installed
gnostr-dev sync --all   # clones and updates everything
gnostr-dev status       # shows dirty, ahead, behind and diverged repos
```

After a sync, your workspace mirrors the remote namespaces:

```
~/Documents/
  .repos.yml
  github.com/
    dxsk/
      my-project/
    my-org/
      other-project/
  gitlab.com/
    my-group/
      sub-group/
        project/
```

On Windows, a host with a port (`git.example.org:3000`) is stored as `git.example.org_3000`, since `:` is not allowed in directory names.

## Usage

### Commands

| Command | What it does |
|---|---|
| `gnostr-dev login [<provider>]` | Logs in to one provider, or to every detected one |
| `gnostr-dev <provider> login` | Same, per provider |
| `gnostr-dev <provider> sync` | Syncs one provider (`github`, `gitlab`, `forgejo`, `bitbucket`, `sourcehut`, `onedev`, `radicle`, `any`) |
| `gnostr-dev sync --all` | Syncs every configured provider |
| `gnostr-dev status` | Lists repos that are dirty, ahead, behind or diverged |
| `gnostr-dev init` | Creates the config file |
| `gnostr-dev update` | Updates the binary in place |
| `gnostr-dev completions <shell>` | Prints a completion script |
| `gnostr-dev version` | Prints the version |

Aliases: `gitea` and `gogs` for `forgejo`, `srht` for `sourcehut`, `git` for `any`.

`sync --all` only runs providers whose CLI, or saved credentials, is available, and one failing host never stops the others. Every provider has its own help: `gnostr-dev github --help`.

### Sync flags

| Flag | Description |
|---|---|
| `--filter <pattern>` | Only sync matching repos (`Dxsk/*` or `Dxsk/project`), repeatable |
| `--ignore <pattern>` | Skip matching repos, repeatable |
| `--base-dir <path>` | Base directory for repos (default: `~/Documents`) |
| `--https` | Use HTTPS clone URLs instead of SSH |
| `--prune` | Remove local repos that no longer exist on the remote |
| `--force` | With `--prune`, go ahead even when most local repos would be removed; with `--write-ignore`, overwrite an existing file |
| `--dry-run` | Show what would be done without changing anything |
| `--plan` | Print the recon summary and stop, cloning nothing |
| `--write-ignore` | Write `<base-dir>/.repos.yml` listing every repo in scope, commented out, then stop |
| `-y`, `--yes` | Clone without asking, however much there is to download |
| `--host <host>` | Target a self-hosted instance (provider sync only) |
| `--parallel <n>` | Number of parallel jobs (default: 4) |
| `-v`, `--verbose` | Show debug output |
| `-q`, `--quiet` | Hide info and success messages (errors still show) |

`status` accepts `--base-dir`, `--verbose` and `--quiet`. `update` accepts `-y` / `--yes`.

### Examples

```sh
# Only one owner, or a single repo
gnostr-dev github sync --filter 'Dxsk/*'
gnostr-dev github sync --filter Dxsk/repos-manager

# Several patterns, and a few exceptions
gnostr-dev sync --all --filter 'Dxsk/*' --filter 'other-org/tooling'
gnostr-dev sync --all --ignore 'Dxsk/old-*'

# A big first sync: look at it, pick what to leave out, then run it
gnostr-dev sync --all --plan
gnostr-dev sync --all --write-ignore
# uncomment in <base-dir>/.repos.yml what you do not want, then
gnostr-dev sync --all

# Or clone everything without being asked
gnostr-dev sync --all --yes

# Preview, then clean up repos deleted on the remote
gnostr-dev sync --all --prune --dry-run
gnostr-dev sync --all --prune

# Self-hosted instances (gitea and gogs are aliases of forgejo)
gnostr-dev gitlab sync --host gitlab.example.org
gnostr-dev forgejo sync --host forge.example.org
gnostr-dev onedev sync --host onedev.example.org

# A plain git server, with no forge API (see "Plain git servers" below)
gnostr-dev any sync --host git.example.org

# HTTPS, more jobs, another base directory
gnostr-dev sync --all --https --parallel 8 --base-dir /path/to/repos
```

Existing clean repos get `git fetch --all --prune`, then a fast-forward of the remote default branch when it is checked out. Any other branch, or a detached HEAD, is only fetched. Repos with uncommitted changes are skipped. `--host` is rejected with `sync --all`.

`--prune` only deletes a local repo when all of these hold:

- the remote no longer lists it;
- it is in scope for that host: allowed by every `only` list that applies to it, and matched by no `ignore` list (see [`.repos.yml`](#filtering));
- it holds no local-only work: no uncommitted or untracked changes, no unpushed commits, no stash;
- it sits inside the base directory.

If more than half of the local repos of a host would go, the remote listing probably came back incomplete (revoked token, API hiccup) and prune stops. Review with `--dry-run`, then add `--force`.

Each host has its own lock, so two syncs of the same host cannot overlap while different hosts sync side by side. The lock is released by the OS if the process dies.

### Before it clones

A sync lists every host first, then says what it is about to do:

```
github.com   42 in scope, 39 cloned, 3 new (1.2 GB)
             biggest new: org/a 586 MB, org/b 586 MB
gitlab.corp  18 in scope, 0 cloned, 18 new (4.7 GB, 2 unknown)
             biggest new: team/monorepo 3.1 GB, team/assets 900 MB
             with --prune: 2 local repos would be deleted

21 clones, 39 updates, about 5.9 GB to download, 2 of unknown size.
Proceed? [Y/n]
```

- The volume covers the new repos only, and it is the size the forge reports on the server, not the size of the transfer, hence **about**. A size a provider does not report shows as `?` and is never estimated.
- You only see this above a threshold, by default 5 new clones or 1 GB across the whole run. A daily sync where nothing is new prints exactly what it always did.
- The question is asked once per run and only when stdin and stdout are both terminals, so cron and CI get the summary and carry on. `-y` and `--dry-run` print it without asking, and `n` exits successfully without cloning.

Two flags turn that summary into a workflow, and neither clones anything:

```sh
gnostr-dev sync --all --plan          # the summary, then stop
gnostr-dev sync --all --write-ignore  # every repo in scope, commented out, into .repos.yml
```

Uncomment in `<base-dir>/.repos.yml` what you do not want, then sync. Thresholds and prompting are set per machine with `confirm_sync`, `confirm_new_repos` and `confirm_download_gb` in the config file. Full rules in the [usage docs](https://repos-manager.dxscloud.fr/docs/usage/).

## Configuration

<details open>
<summary><b>Config file</b></summary>

<br>

`gnostr-dev init` creates `~/.config/gnostr-dev/config.json`. The path is the same on every OS, including Windows (`%USERPROFILE%\.config\gnostr-dev\config.json`), and `GNOSTR_DEV_CONFIG` overrides it. The older `REPOS_MANAGER_CONFIG` is still read.

```json
{
  "base_dir": "~/Documents",
  "parallel": 4,
  "protocol": "ssh",
  "check_updates": true,
  "scan_network_mounts": false,
  "gitlab_statistics": true,
  "confirm_sync": "auto",
  "confirm_new_repos": 5,
  "confirm_download_gb": 1,
  "hosts": {
    "github":    ["github.com"],
    "gitlab":    ["gitlab.com", "gitlab.example.org"],
    "forgejo":   ["codeberg.org", "forge.example.org"],
    "bitbucket": ["bitbucket.org", "bitbucket.example.org"],
    "sourcehut": ["git.sr.ht"],
    "onedev":    ["onedev.example.org"]
  },
  "repos": {
    "git.example.org": ["git@git.example.org:infra/ansible.git"]
  }
}
```

| Field | Default | Description |
|---|---|---|
| `base_dir` | `~/Documents` | Where repos are cloned |
| `parallel` | `4` | Parallel sync jobs |
| `protocol` | `ssh` | `ssh` or `https` |
| `check_updates` | `true` | Background update check, see [Updating](#updating) |
| `scan_network_mounts` | `false` | Let `status` walk network and FUSE mounts (Linux) |
| `gitlab_statistics` | `true` | Ask GitLab for repository sizes (a heavier listing); `false` keeps the light listing and sizes stay unknown |
| `confirm_sync` | `auto` | When a sync asks before cloning: `auto` over the thresholds below, `always` as soon as there is anything to do, `never` for no question at all (a big run is still summarized) |
| `confirm_new_repos` | `5` | New clones, run-wide, that make `auto` ask |
| `confirm_download_gb` | `1` | Gigabytes to download, run-wide, that make `auto` ask |
| `hosts.<provider>` | provider's SaaS host | One hostname or a list. Each one is synced into its own `<base_dir>/<host>/` |
| `repos.<host>` | none | Plain git servers, see the **Plain git servers** block below |

OneDev and plain git servers are self-hosted only and have no default host: nothing is synced until you name one.

Self-hosted instances need a matching login: `gh auth login --hostname <host>`, `glab auth login --hostname <host>`, `tea login add` or `gnostr-dev <provider> login`.

Precedence: flag > environment variable > config file > default.

</details>

<details>
<summary><b>Plain git servers</b></summary>

<br>

The `any` provider syncs servers that have no forge API at all, including a bare `git init --bare` on a VPS. Its hosts are the keys of `repos`, and each one gets its own directory like any other host. There is nothing to log in to: these hosts use your SSH keys.

List the clone URLs by hand:

```json
{
  "repos": {
    "git.example.org": [
      "git@git.example.org:infra/ansible.git",
      "ssh://me@vps.example.org:2222/srv/git/notes.git",
      "https://git.example.org/a/b/c.git"
    ]
  }
}
```

The local path comes from the URL, so those three land in `infra/ansible`, `srv/git/notes` and `a/b/c` under their host directory. A URL you listed is used exactly as written, so `--https` does not rewrite it.

Or let the server list itself, when it knows how:

```json
{
  "repos": {
    "gitolite.example.org": { "discover": "gitolite", "user": "git" },
    "soft.example.org":     { "discover": "soft-serve", "port": 23231 },
    "vps.example.org":      { "discover": "find:/srv/git", "user": "me", "port": 2222 }
  }
}
```

| `discover` | What runs | Notes |
|---|---|---|
| `gitolite` | `ssh [-p <port>] <user>@<host> info` | `user` defaults to `git`. Config patterns (`CREATOR`, wildcards) are not repos and are dropped |
| `soft-serve` | `ssh -p <port> <host> repo list` | `port` defaults to 23231, [Soft Serve](https://github.com/charmbracelet/soft-serve)'s default |
| `find:<root>` | `find <root> -name '*.git' -prune` over SSH | Needs a real shell on the remote account, so it does not work with `git-shell` |

`urls` and `discover` can be combined in one entry, and both are synced.

Discovery runs with `BatchMode=yes` and a connect timeout, so an unknown host key or a key with no agent fails with a message instead of stalling the sync.

</details>

<details>
<summary><b>Credential files</b></summary>

<br>

Providers without a CLI (or whose CLI you did not install) keep a token per host under `~/.config/gnostr-dev/`, written by `gnostr-dev <provider> login` with mode `0600` on unix. Each file is a JSON map keyed by host, so several instances coexist.

| File | Written by | Shape |
|---|---|---|
| `bitbucket-creds` | `gnostr-dev bitbucket login` | `{"bitbucket.org":{"user":"me@example.com","token":"..."}}` |
| `forgejo-creds` | `gnostr-dev forgejo login` | `{"git.example.org":{"url":"https://git.example.org","token":"..."}}` |
| `onedev-creds` | `gnostr-dev onedev login` | `{"onedev.example.org":{"user":"me","token":"..."}}` |

**Bitbucket Cloud:** app passwords were removed by Atlassian on 2026-07-28. Use an [Atlassian API token](https://id.atlassian.com/manage-profile/security/api-tokens) with your account email as the user. An old single-line `user:password` file is still read, with a warning telling you to log in again.

**Bitbucket Data Center:** any host other than `bitbucket.org` uses an HTTP access token (*profile picture > Manage account > HTTP access tokens*). Leave the user empty and it is sent as a Bearer, which is what project- and repository-scoped tokens require.

**Forgejo / Gitea / Gogs:** a matching `tea` login wins over this file. The file is what makes Gogs work, since `tea login add` may refuse a Gogs server.

**OneDev:** create the token at `https://<host>/~my/access-tokens`. Git over SSH uses OneDev's own port, 6611, which must be reachable unless you sync with `--https`.

</details>

<details id="filtering">
<summary><b>Filtering: .repos.yml</b></summary>

<br>

One file at the root of the base directory decides what gets synced, globally and per host:

```yaml
# Everywhere
only:
  - Dxsk/*
ignore:
  - test-org/*

# Per host, on top of the lists above
hosts:
  gitlab.corp:
    only: [team/*]
    ignore: [team/archive-*]
  github.com:
    ignore: [Dxsk/old-project]
```

`only` is an allow-list, one matching pattern is enough. `ignore` is a deny-list, and a repo it catches is reported as `ignored`. Allow-lists stack and a repo must pass all of them (`--filter` flags, then the host block, then the global list) while deny-lists add up. So a `hosts:` block can only narrow what the global lists allow, and it can never pull a repository into the reach of `--prune`.

Patterns use `*` and `?`, `owner/*` also matches nested paths, and they are matched against the remote full name rather than the local path. Host keys ignore case.

Since this file drives `--prune`, a typo in it is an error, not a shrug: an unknown key, malformed YAML or an unreadable file stops the run before any host is synced.

`gnostr-dev sync --all --write-ignore` writes the file for you, holding every repository in scope with its size, all commented out. `.repos-filter` and `.repos-ignore` keep working as in 1.0 while there is no `.repos.yml`.

Pattern syntax, stacking order and the generated file in detail: [filtering docs](https://repos-manager.dxscloud.fr/docs/filtering/).

</details>

<details>
<summary><b>Environment variables</b></summary>

<br>

| Variable | Description | Default |
|---|---|---|
| `GNOSTR_DEV_CONFIG` | Path to the config file | `~/.config/gnostr-dev/config.json` |
| `GNOSTR_DEV_BASE_DIR` | Base directory for all repos | `~/Documents` |
| `GNOSTR_DEV_PARALLEL` | Default parallel jobs | `4` |
| `GNOSTR_DEV_PROTOCOL` | Default protocol (`ssh` or `https`) | `ssh` |
| `GNOSTR_DEV_NO_UPDATE_CHECK` | Set to `1` to skip the background update check | unset |
| `GNOSTR_DEV_UPDATE_TTL` | Seconds between update checks | `86400` |
| `GNOSTR_DEV_UPDATE_CACHE` | Path to the cached latest-version file | `<cache dir>/gnostr-dev/latest-version` |
| `GNOSTR_DEV_GIT_TIMEOUT` | Seconds before a single git command is killed | `3600` |
| `GNOSTR_DEV_LIST_TIMEOUT` | Seconds before a provider CLI listing is killed | `300` |
| `GNOSTR_DEV_UPDATE_URL` | Release API used by the update check and `update` | This repository's GitHub Releases API |
| `TEA_CONFIG` | Path to tea's config file, read by the Forgejo provider | tea's default location |
| `NO_COLOR` | Disable colored output | unset |

The older `REPOS_MANAGER_*` names are still read next to the `GNOSTR_DEV_*`
ones, so the setups that predate the rename keep working. The `GNOSTR_DEV_*`
name wins when both are set.

</details>

<details>
<summary><b>Fast status on large workspaces</b></summary>

<br>

`status` skips vendored directories (`node_modules`, `.venv`, `target`, `vendor`, `dist` and friends) and shows a live progress line while it scans.

On Linux it also reads `/proc/self/mountinfo` and prunes every mount under `base_dir` whose filesystem is `fuse`, `fuse.*`, `nfs`, `cifs`, `smb*`, `smbfs`, `afs`, `ceph` or `davfs`. Cloud drives (kDrive, Dropbox, sshfs) mounted under `~/Documents` would otherwise make the scan crawl. Set `"scan_network_mounts": true` if you really host repos on a reliable network share.

</details>

## Shell completions

The binary generates them for bash, zsh, fish, PowerShell and elvish:

```sh
gnostr-dev completions bash > ~/.local/share/bash-completion/completions/gnostr-dev
gnostr-dev completions zsh  > ~/.local/share/zsh/site-functions/_gnostr-dev
gnostr-dev completions fish > ~/.config/fish/completions/gnostr-dev.fish
```

```powershell
# Add this line to your $PROFILE to keep it
gnostr-dev completions powershell | Out-String | Invoke-Expression
```

From a source checkout, `make completions` installs the bash, zsh and fish files for you.

## Updating

Commands that touch repositories print a one-line banner when a newer release is out:

```
⬆ gnostr-dev 1.1.0 available (current 1.0.0), run: gnostr-dev update
```

The banner reads a cached version, refreshed at most once a day by a detached background process that queries the GitHub Releases API, so the check never slows down the command in progress. Turn it off with `"check_updates": false`, or with `GNOSTR_DEV_NO_UPDATE_CHECK=1` for a single run.

```sh
gnostr-dev update      # asks for confirmation
gnostr-dev update -y   # no prompt
```

`update` downloads the release asset of this repository for your platform (the `msvc` zip on Windows), verifies it against the release's `SHA256SUMS` and replaces the binary in place. It follows the releases of this repository, not the upstream ones: an upstream release carries a binary that calls itself `repos-manager`, and installing it in place would replace `gnostr-dev` with a tool of another name.

Installed through a package manager (AUR, `cargo install`, and later Homebrew, Scoop or winget)? Then `update` does not touch the binary and the banner shows the package manager's command instead, for example `run: cargo install gnostr-dev`.

### Upgrading from 0.x

The 0.x tool was the upstream Bash script, called `repos-manager`. 1.0 was a breaking release of it: the Bash tool became a native binary, and the 0.x `repos-manager update` cannot install it. Your config file, `.repos-filter`, `.repos-ignore` and synced repositories are kept as they are (the two filter files are still read, see [Filtering](#filtering)).

```sh
# 1. Remove the 0.x Bash install (make install put it here)
rm -f ~/.local/bin/repos-manager
rm -rf ~/.local/lib/repos-manager

# 2. Install the native binary
make install                    # or: just install

# 3. Shell integration: drop the old `source .../sourceme*` lines from your
#    shell rc file, delete the generated files, and use completions instead
find ~/Documents -maxdepth 2 -name 'sourceme*' -delete   # adjust to your base_dir
# then set up completions with: gnostr-dev completions <shell> (see Shell completions)
```

Nix users: the flake is gone, use one of the install methods above. If you set `REPOS_MANAGER_VERSION_URL`, it is now `GNOSTR_DEV_UPDATE_URL` and points to a GitHub Releases API URL.

## Development

<details>
<summary><b>Building and testing</b></summary>

<br>

```sh
make build     # optimized binary in target/release/
make test      # unit and integration tests
make coverage  # tests plus line coverage (needs cargo-llvm-cov and LLVM tools)
make lint      # rustfmt and clippy
```

Tests shell out to the real `git` with bare remotes in temporary directories, so they need git 2.28 or newer. Run the CLI without installing it with `cargo run -- github sync --dry-run --base-dir /tmp/rm`.

The scripts in `installers/` and the packages in `packaging/` are the upstream's: they install the upstream build, which calls itself `repos-manager`. To build the upstream Windows installer yourself, install [NSIS](https://nsis.sourceforge.io) and run:

```powershell
cargo build --release
makensis /DVERSION=1.0.0 /DARCH=x86_64 /DBINARY="$PWD\target\release\gnostr-dev.exe" installers\repos-manager.nsi
```

`repos-manager-x86_64-setup.exe` is written next to the script unless you pass `/DOUTFILE=path`. The script installs the binary under the upstream's name, `repos-manager.exe`.

The contributing guide of the upstream project is on the [documentation site](https://repos-manager.dxscloud.fr/docs/contributing/). Issues and pull requests of this tool go to [GitHub](https://github.com/RandyMcMillan/radicle.dev/issues). Report vulnerabilities privately through a [security advisory](https://github.com/RandyMcMillan/radicle.dev/security/advisories/new).

</details>

<details>
<summary><b>CI and releases</b></summary>

<br>

This tool lives in [radicle.dev](https://github.com/RandyMcMillan/radicle.dev). Its pipeline is `.github/workflows/gnostr-dev.yml`:

| When | What |
|---|---|
| On every push and pull request | Build and test on Linux and macOS, `rustfmt`, `clippy`, ShellCheck and the python check |
| Every night | The dependency list of `Cargo.toml` is refreshed from the crates.io search, and the job fails when the result differs from the committed file |

The same jobs run locally, in a container, with [act](https://github.com/nektos/act): `just act-lint`, `just act-build`, `just act-test` and `just act-all`.

</details>

<details>
<summary><b>Cutting a release</b></summary>

<br>

1. Describe the changes under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md).
2. Run the release script with the new version:

   ```sh
   python scripts/release.py 1.1.0    # or: make release V=1.1.0
   ```

   The working tree must be clean. It sets the version in `Cargo.toml`, `Cargo.lock` and `gnostr-dev.sh`, turns the `Unreleased` heading into `## 1.1.0 (date)`, then commits `chore: release v1.1.0` and creates the signed `v1.1.0` tag (`git tag -s`, so a GPG signing key is needed). Nothing is pushed yet, so you can still check the result.

   `make release` just calls the script, so a checkout without `make` loses nothing. On Windows the signing key usually lives in the GnuPG keyring rather than the one Git Bash reads: `git config --global gpg.program` has to point at `gpg.exe` for the tag to sign.
3. Push the branch and the tag:

   ```sh
   git push origin main v1.1.0
   ```

There is no automatic version bump: the version only changes through the release script.

</details>

## License

[MIT](LICENSE)
