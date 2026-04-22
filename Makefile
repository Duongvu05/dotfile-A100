.PHONY: install help

help:
	@echo "Usage:"
	@echo "  make install   Run bootstrap (cài uv + huggingface-cli)"

install:
	@bash install.sh
