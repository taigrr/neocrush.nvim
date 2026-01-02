.PHONY: test lint format demo

test:
	nvim --headless --noplugin -u scripts/minimal_init.vim \
		-c "PlenaryBustedDirectory tests/ { minimal_init = './scripts/minimal_init.vim' }"

lint:
	stylua --check lua/

format:
	stylua lua/ tests/

# Generate demo GIFs locally
# Requires: brew install vhs
demo:
	PLUGIN_PATH=$(PWD) vhs demo/demo.tape
