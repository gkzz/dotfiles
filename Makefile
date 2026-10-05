.DEFAULT_GOAL := help

.PHONY: help setup install install-apply verify verify-dotfiles uninstall uninstall-apply verify-uninstalled ci lint test test-bootstrap-dry-run test-bootstrap-packages-dry-run test-git-hooks

MISE_BOOTSTRAP_ARGS ?=

export PATH := $(HOME)/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$(PATH)
MISE := $(shell command -v mise 2>/dev/null || if [ -x "$(HOME)/.local/bin/mise" ]; then printf '%s' "$(HOME)/.local/bin/mise"; fi)
MISE_CONFIG := $(CURDIR)/mise.toml
MISE_RUN = MISE_CONFIG_FILE="$(MISE_CONFIG)" MISE_TRUSTED_CONFIG_PATHS="$(CURDIR)" $(MISE)

help:
	@printf '%s\n' 'Targets:'
	@printf '  %-24s %s\n' 'make setup' 'Prepare Homebrew and mise'
	@printf '  %-24s %s\n' 'make install' 'Preview mise bootstrap'
	@printf '  %-24s %s\n' 'make install-apply' 'Apply mise bootstrap'
	@printf '  %-24s %s\n' 'make verify' 'Check mise bootstrap status'
	@printf '  %-24s %s\n' 'make verify-dotfiles' 'Check mise-managed dotfiles status'
	@printf '  %-24s %s\n' 'make uninstall' 'Preview dotfile removal'
	@printf '  %-24s %s\n' 'make uninstall-apply' 'Remove mise-managed dotfiles'
	@printf '  %-24s %s\n' 'make ci' 'Run lint and test sequentially'
	@printf '  %-24s %s\n' 'make lint' 'Run Bash syntax checks'
	@printf '  %-24s %s\n' 'make test-bootstrap-dry-run' 'Dry-run bootstrap without packages or dotfiles'
	@printf '  %-24s %s\n' 'make test-bootstrap-packages-dry-run' 'Dry-run Homebrew package bootstrap'
	@printf '  %-24s %s\n' 'make test-git-hooks' 'Run existing Git hook tests'

setup:
	./setup/init.sh

install:
	$(MISE_RUN) bootstrap --dry-run $(MISE_BOOTSTRAP_ARGS)

install-apply:
	$(MISE_RUN) bootstrap --yes $(MISE_BOOTSTRAP_ARGS)

verify:
	$(MISE_RUN) bootstrap status --missing

verify-dotfiles:
	$(MISE_RUN) bootstrap dotfiles status --missing

uninstall:
	$(MISE_RUN) bootstrap dotfiles unapply --dry-run

uninstall-apply:
	$(MISE_RUN) bootstrap dotfiles unapply --yes

verify-uninstalled:
	@$(MISE_RUN) bootstrap dotfiles status --json | jq -e '.files | length == 5 and all(.[]; .state == "missing")' >/dev/null

ci:
	$(MAKE) lint
	$(MAKE) test

lint:
	bash -n git/hooks/pre-commit setup/*.sh bash/*.bash .bashrc .bash_profile

test: test-bootstrap-dry-run test-git-hooks

test-bootstrap-dry-run:
	$(MISE_RUN) bootstrap --dry-run --skip packages,dotfiles

test-bootstrap-packages-dry-run:
	$(MISE_RUN) bootstrap --dry-run --only packages

test-git-hooks:
	$(MISE_RUN) exec -- node --test --test-isolation=none --test-concurrency=1 tests/git-hooks.test.js
