.DEFAULT_GOAL := help

.PHONY: help install install-apply verify uninstall uninstall-apply gcm gcm-apply check lint test

help:
	@printf '%s\n' 'Targets:'
	@printf '  %-24s %s\n' 'make install' 'dry-run package, tool, and symlink convergence'
	@printf '  %-24s %s\n' 'make install-apply' 'Apply package, tool, and symlink convergence'
	@printf '  %-24s %s\n' 'make verify' 'Verify installed lifecycle state'
	@printf '  %-24s %s\n' 'make uninstall' 'dry-run managed symlink removal'
	@printf '  %-24s %s\n' 'make uninstall-apply' 'Remove managed symlinks'
	@printf '  %-24s %s\n' 'make gcm' 'dry-run Git Credential Manager setup'
	@printf '  %-24s %s\n' 'make gcm-apply' 'Configure Git Credential Manager'
	@printf '  %-24s %s\n' 'make check' 'Run lint and test sequentially'
	@printf '  %-24s %s\n' 'make lint' 'Run Bash syntax checks and Biome'
	@printf '  %-24s %s\n' 'make test' 'Run Node.js tests and mise boundary test'

install:
	./bin/dotfiles install

install-apply:
	./bin/dotfiles install --apply

verify:
	./bin/dotfiles verify

uninstall:
	./bin/dotfiles uninstall

uninstall-apply:
	./bin/dotfiles uninstall --apply

gcm:
	./setup/gcm.sh --dry-run

gcm-apply:
	./setup/gcm.sh --apply

check:
	$(MAKE) lint
	$(MAKE) test

lint:
	bash -n bin/dotfiles setup/*.bash setup/*.sh tests/*.sh tests/fixtures/*.bash tests/integration/*.sh bash/*.bash .bashrc .bash_profile
	mise --cd .config/mise exec -- biome check --config-path "$$(pwd)/biome.jsonc" "$$(pwd)/tests"

test:
	./tests/run.sh
	./tests/integration/mise-isolation.sh
