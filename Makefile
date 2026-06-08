.PHONY: install startup help

help:
	@echo "Usage:"
	@echo "  make install    First-time bootstrap (installs all tools)"
	@echo "  make startup    Run on every pod restart"
	@echo "  bash setup.sh install"
	@echo "  bash setup.sh"

install:
	@bash setup.sh install

startup:
	@bash setup.sh
