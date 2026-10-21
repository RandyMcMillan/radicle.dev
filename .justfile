# The commands of this repository. Run `just` to list them.
#
# `just --help` explains the syntax; https://just.systems is the manual.

set shell := ["bash", "-euo", "pipefail", "-c"]

# The command the tool installs under. That is the name the tool prints, the
# name of its config directory, the name cargo writes the binary under and
# the name its releases are published under.
name := "gnostr-dev"

# The Cargo package. It carries the same name as the command, so the file in
# the build output and the command on the PATH are one and the same.
package := name

# Where the command is installed. PREFIX overrides it.
prefix := env_var_or_default("PREFIX", home_dir() / ".local")

# cargo can write the build output somewhere else (build.target-dir), so ask
# it where the binary ends up instead of guessing.
target_dir := `cargo metadata --format-version 1 --no-deps 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])' 2>/dev/null || echo target`

bin := target_dir / "release" / package

bash_comp := home_dir() / ".local" / "share" / "bash-completion" / "completions" / name
zsh_comp := home_dir() / ".local" / "share" / "zsh" / "site-functions" / ("_" + name)
fish_comp := home_dir() / ".config" / "fish" / "completions" / (name + ".fish")

# The flags that reproduce the crates.io dependency list, in one place.
crates_flags := `grep -v '^[[:space:]]*#' scripts/crates-flags | tr '\n' ' '`

# The image act runs the ubuntu jobs in.
act_image := "catthehacker/ubuntu:full-latest"

# The workflow and the flags every act run needs. The jobs that use a
# matrix do not resolve an image of their own - act starts them with an
# empty one - so the platform is mapped to an image and the matrix is picked
# with --matrix. macOS cannot run in a linux container, so those legs are
# skipped unless they are mapped to the ubuntu image on purpose.
act_flags := "-W .github/workflows/gnostr-dev.yml --container-architecture linux/amd64 -P ubuntu-latest=" + act_image

# List the commands.
default:
    @just --list

# Build the release binary.
build:
    cargo build --release --locked

# Check every target without linking.
check:
    cargo check --locked --all-targets

# Run the tests.
test:
    cargo test --locked

# Test coverage. Needs cargo-llvm-cov: cargo install cargo-llvm-cov.
# Also needs the LLVM tools (llvm-cov, llvm-profdata) from rustup's
# llvm-tools-preview component or a system LLVM such as Homebrew's.
coverage:
    LLVM_COV="${LLVM_COV:-$(command -v llvm-cov || echo /opt/homebrew/opt/llvm/bin/llvm-cov)}" LLVM_PROFDATA="${LLVM_PROFDATA:-$(command -v llvm-profdata || echo /opt/homebrew/opt/llvm/bin/llvm-profdata)}" cargo llvm-cov --locked --summary-only

# Format the code.
fmt:
    cargo fmt

# Check the formatting.
fmt-check:
    cargo fmt --check

# Lint with clippy.
clippy:
    cargo clippy --all-targets --locked -- -D warnings

# Lint the shell scripts. Needs shellcheck.
shellcheck:
    shellcheck scripts/*.sh installers/install.sh gnostr-dev.sh

# Check the python scripts.
python-check:
    python3 -m compileall -q scripts

# Check the workflow files. Needs actionlint.
workflows:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v actionlint >/dev/null 2>&1; then
      echo "actionlint is not installed, nothing to check"
      exit 0
    fi
    actionlint .github/workflows/*.yml

# What CI runs on a pull request.
lint: fmt-check clippy shellcheck python-check workflows

# Build, lint and test, the way CI does.
ci: fmt-check clippy test

# Run the tool from the build output: just run status
run *args: build
    "{{bin}}" {{args}}

# Install the command into PREFIX/bin.
install: build
    install -d "{{prefix}}/bin"
    install -m755 "{{bin}}" "{{prefix}}/bin/{{name}}"
    @echo "Installed {{prefix}}/bin/{{name}}"

# Remove the installed command.
uninstall:
    rm -f "{{prefix}}/bin/{{name}}"

# Install the shell completions.
completions: build
    install -d "$(dirname {{bash_comp}})" "$(dirname {{zsh_comp}})" "$(dirname {{fish_comp}})"
    "{{bin}}" completions bash > "{{bash_comp}}"
    "{{bin}}" completions zsh > "{{zsh_comp}}"
    "{{bin}}" completions fish > "{{fish_comp}}"
    @echo "For zsh, make sure $(dirname {{zsh_comp}}) is in your fpath."

# Remove the shell completions.
uninstall-completions:
    rm -f "{{bash_comp}}" "{{zsh_comp}}" "{{fish_comp}}"

# Refresh the crates.io dependency list in Cargo.toml.
crates:
    scripts/update-crates.sh {{crates_flags}}

# Print what the crates.io search resolves to, change nothing.
crates-dry-run:
    scripts/update-crates.sh --dry-run {{crates_flags}}

# Check that Cargo.toml still matches the crates.io search, without touching it.
crates-check:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cp Cargo.toml "$tmp/Cargo.toml"
    scripts/update-crates.sh --manifest "$tmp/Cargo.toml" {{crates_flags}}
    if ! diff -u Cargo.toml "$tmp/Cargo.toml"; then
        echo
        echo "Cargo.toml is out of date. Run 'just crates' and commit the result."
        exit 1
    fi
    echo "Cargo.toml is up to date"

# Clone the repositories of the radicle organization from the Radicle network.
clone *args:
    scripts/clone-radicle-dev.sh {{args}}

# Clone the repositories of the radicle organization from GitHub.
clone-github *args:
    scripts/clone-radicle-dev.sh --github {{args}}

# Cut a release: just release 1.2.0
release version:
    python3 scripts/release.py {{version}}

# Per-function complexity budgets. Needs rust-code-analysis-cli.
metrics:
    python3 scripts/code-metrics.py

# Mutation testing on the files the sync touches. Needs cargo-mutants.
mutants:
    cargo mutants --file src/sync/mod.rs --file src/sync/paths.rs --file src/sync/jobs.rs --file src/sync/prune.rs --file src/git.rs -j 2 --timeout-multiplier 5

# Remove the build output.
clean:
    cargo clean

# List the jobs of the workflow.
act-list:
    act -W .github/workflows/gnostr-dev.yml --list

# Pull the image act runs the jobs in.
act-pull:
    docker pull {{act_image}}

# Run the lint job in docker.
act-lint:
    act {{act_flags}} -j lint

# Run the build job in docker, on the ubuntu runner.
act-build:
    act {{act_flags}} -j build --matrix "os:ubuntu-latest"

# Run the test job in docker, on the ubuntu runner.
act-test:
    act {{act_flags}} -j test --matrix "os:ubuntu-latest"

# The job only runs on a schedule or on workflow_dispatch, so the event has
# to be one of those.

# Run the manifest job in docker.
act-manifest:
    act {{act_flags}} -j manifest --event workflow_dispatch

# The build compiles the whole radicle ecosystem from scratch in the
# container, so this takes a while. Mount the cargo registry to reuse it:
#
#   act --container-options "--volume $HOME/.cargo:/root/.cargo"

# Run every job in docker, on the ubuntu runner.
act-all:
    act {{act_flags}} --matrix "os:ubuntu-latest" --event workflow_dispatch
