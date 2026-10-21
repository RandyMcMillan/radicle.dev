#!/usr/bin/env bash
# Transitional stub, kept for a while after 1.0. 0.x (Bash) installs read
# VERSION from this file on GitHub main to show their update banner, and
# git-clone installs execute it after `gnostr-dev update` pulls.
VERSION="0.1.0"

cat >&2 <<EOF
gnostr-dev ${VERSION} is a native binary and replaces the 0.x Bash script.
The 0.x updater cannot install it, please reinstall:

  rm -f ~/.local/bin/gnostr-dev && rm -rf ~/.local/lib/gnostr-dev
  make install

Your config and synced repositories are kept. Full guide:
https://github.com/RandyMcMillan/radicle.dev#upgrading-from-0x
EOF
exit 1
