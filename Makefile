.PHONY: help install uninstall test lint check doctor clean dev-setup

VERSION := $(shell cat VERSION)

help:
	@echo "gh-accounts Development Makefile"
	@echo ""
	@echo "Installation:"
	@echo "  make install          Install system-wide (requires sudo)"
	@echo "  make uninstall        Uninstall system-wide (requires sudo)"
	@echo ""
	@echo "Testing & Linting:"
	@echo "  make test             Run BATS test suite"
	@echo "  make lint             Run ShellCheck linting"
	@echo "  make check            Run lint + test"
	@echo ""
	@echo "Setup:"
	@echo "  make dev-setup        Install dev dependencies"

install:
	sudo bash install.sh

uninstall:
	sudo bash uninstall.sh

dev-setup:
	sudo apt-get update && sudo apt-get install -y bats shellcheck

test:
	bats tests/*.bats

lint:
	shellcheck -x bin/* lib/*.sh install.sh uninstall.sh

check: lint test

doctor:
	bash bin/gh-accounts doctor

clean:
	rm -rf ~/.ssh/gh-accounts-backups/* 2>/dev/null || true
