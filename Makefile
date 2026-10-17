SHELL := /bin/bash
SCRIPTS := bin/grokbot-lite install.sh
.PHONY: all lint test crosscheck chart check-units

all: lint test

lint:
	shellcheck $(SCRIPTS) tests/helpers/common.bash
	shellcheck -s sh compat/detect.sh

test:
	bats tests/

crosscheck:
	mkdir -p .cache/fuses && cd .cache/fuses && [ -d node_modules/@electron/fuses ] || (npm init -y >/dev/null && npm i --no-audit --no-fund @electron/fuses@2)
	GBL_TEST_ELECTRON_FUSES=$(CURDIR)/.cache/fuses bats tests/fuse.bats

chart:
	python3 scripts/gen-chart.py

check-units:
	systemd-analyze --user verify systemd/grokbot-lite-doctor.timer || true
