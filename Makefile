.DEFAULT_GOAL := help

.PHONY: help setup install install-apply verify verify-dotfiles uninstall uninstall-apply verify-uninstalled ci lint test test-bootstrap-dry-run test-bootstrap-packages-dry-run test-git-hooks

export MISE_BOOTSTRAP_ARGS ?=

export PATH := $(HOME)/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$(PATH)
MISE := $(shell command -v mise 2>/dev/null || if [ -x "$(HOME)/.local/bin/mise" ]; then printf '%s' "$(HOME)/.local/bin/mise"; fi)
MISE_CONFIG := $(CURDIR)/mise-operations.toml
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

# Operation implementations live in mise-operations.toml; setup/help work without mise.
install:
	$(MISE_RUN) run dotfiles:install

install-apply:
	$(MISE_RUN) run dotfiles:install:apply

verify:
	$(MISE_RUN) run dotfiles:verify

verify-dotfiles:
	$(MISE_RUN) run dotfiles:verify:dotfiles

uninstall:
	$(MISE_RUN) run dotfiles:uninstall

uninstall-apply:
	$(MISE_RUN) run dotfiles:uninstall:apply

verify-uninstalled:
	$(MISE_RUN) run dotfiles:verify:uninstalled

ci:
	$(MISE_RUN) run dotfiles:ci

lint:
	$(MISE_RUN) run dotfiles:lint

test:
	$(MISE_RUN) run dotfiles:test

test-bootstrap-dry-run:
	$(MISE_RUN) run dotfiles:test:bootstrap-dry-run

test-bootstrap-packages-dry-run:
	$(MISE_RUN) run dotfiles:test:bootstrap-packages-dry-run

test-git-hooks:
	$(MISE_RUN) run dotfiles:test:git-hooks
