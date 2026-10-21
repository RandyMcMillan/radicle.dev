PREFIX ?= $(HOME)/.local
# The Cargo package is called gnostr-dev - crates.io has a crate named
# repos-manager, which the dependency list needs, so the package cannot be
# called that - and cargo therefore writes the binary under that name. The
# command installs as gnostr-dev: that is the name the tool prints, the
# name of its config directory and the name its releases are published
# under.
NAME   := gnostr-dev
# python3 everywhere but Windows, where it is a Microsoft Store stub that
# exits non-zero instead of running anything.
PYTHON ?= $(shell python3 -c "" >/dev/null 2>&1 && echo python3 || echo python)
# cargo can write the build output somewhere else (build.target-dir), so ask
# it where the binary ends up instead of guessing.
TARGET_DIR := $(shell cargo metadata --format-version 1 --no-deps 2>/dev/null | $(PYTHON) -c 'import json,sys; print(json.load(sys.stdin)["target_directory"])' 2>/dev/null)
BIN    := $(if $(TARGET_DIR),$(TARGET_DIR)/release/gnostr-dev,target/release/gnostr-dev)

BASH_COMP := $(HOME)/.local/share/bash-completion/completions/gnostr-dev
ZSH_COMP  := $(HOME)/.local/share/zsh/site-functions/_gnostr-dev
FISH_COMP := $(HOME)/.config/fish/completions/gnostr-dev.fish

build:
	@command -v cargo >/dev/null || { echo "cargo not found: install Rust (https://rustup.rs) or use installers/install.sh"; exit 1; }
	cargo build --release --locked

test:
	cargo test --locked

# Needs cargo-llvm-cov: cargo install cargo-llvm-cov
# cargo-llvm-cov also needs the LLVM tools (llvm-cov, llvm-profdata). They are
# provided by rustup's llvm-tools-preview component, or by a system LLVM such
# as Homebrew's. Detect them here so `make coverage` works without the user
# having to export LLVM_COV/LLVM_PROFDATA by hand.
LLVM_COV ?= $(shell command -v llvm-cov 2>/dev/null)
LLVM_PROFDATA ?= $(shell command -v llvm-profdata 2>/dev/null)

ifeq ($(LLVM_COV),)
ifneq ($(wildcard /opt/homebrew/opt/llvm/bin/llvm-cov),)
LLVM_COV := /opt/homebrew/opt/llvm/bin/llvm-cov
LLVM_PROFDATA := /opt/homebrew/opt/llvm/bin/llvm-profdata
endif
endif

ifeq ($(LLVM_COV),)
ifneq ($(wildcard /usr/local/opt/llvm/bin/llvm-cov),)
LLVM_COV := /usr/local/opt/llvm/bin/llvm-cov
LLVM_PROFDATA := /usr/local/opt/llvm/bin/llvm-profdata
endif
endif

coverage:
	@command -v cargo >/dev/null || { echo "cargo not found: install Rust (https://rustup.rs) or use installers/install.sh"; exit 1; }
	LLVM_COV="$(LLVM_COV)" LLVM_PROFDATA="$(LLVM_PROFDATA)" cargo llvm-cov --locked --summary-only

lint:
	cargo fmt --check
	cargo clippy --all-targets --locked -- -D warnings

# Per-function complexity budgets, measured with Mozilla's rust-code-analysis.
# Needs the analyser: cargo install rust-code-analysis-cli --locked
metrics:
	$(PYTHON) scripts/code-metrics.py

# Rewrites one expression at a time and checks that a test notices. A mutant
# that survives is behaviour nothing pins down. The whole suite runs per
# mutant, so this is slow; CI only mutates what a pull request changes.
# Needs cargo-mutants: cargo install cargo-mutants --locked
mutants:
	cargo mutants --file src/sync/mod.rs --file src/sync/paths.rs --file src/sync/jobs.rs --file src/sync/prune.rs --file src/git.rs -j 2 --timeout-multiplier 5

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m755 $(BIN) $(DESTDIR)$(PREFIX)/bin/$(NAME)

uninstall: uninstall-completions
	rm -f $(DESTDIR)$(PREFIX)/bin/$(NAME)

completions: build
	install -d $(dir $(BASH_COMP)) $(dir $(ZSH_COMP)) $(dir $(FISH_COMP))
	$(BIN) completions bash > $(BASH_COMP)
	$(BIN) completions zsh > $(ZSH_COMP)
	$(BIN) completions fish > $(FISH_COMP)
	@echo "For zsh, make sure $(dir $(ZSH_COMP)) is in your fpath."

uninstall-completions:
	rm -f $(BASH_COMP) $(ZSH_COMP) $(FISH_COMP)

clean:
	cargo clean

# make release V=1.1.0
# Bumps the version, dates the "Unreleased" changelog section, commits and
# tags. Pushing the tag to Forgejo (and the mirror) triggers the releases.
# The steps live in the script so a checkout without make can cut a release.
release:
	@test -n "$(V)" || { echo "usage: make release V=x.y.z"; exit 1; }
	$(PYTHON) scripts/release.py $(V)

.PHONY: build test coverage lint metrics mutants install uninstall completions uninstall-completions clean release
