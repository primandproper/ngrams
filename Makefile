# PATHS
GENERATOR_DIR := generator
GENERATOR_PKG := github.com/verygoodsoftwarenotvirus/ngrams/$(GENERATOR_DIR)
SCRIPTS_DIR   := scripts
RAW_DATA_DIR  := data/raw
BLOCKLIST_DIR := data/blocklists
BANK_FILE     := data/bank/puzzles.json

# BANK
# The committed bank starts here. Moving the start or seed regenerates every board.
BANK_START := 2026-10-23
BANK_DAYS  := 90
BANK_SEED  := 1

# CONTAINER VERSIONS
LINTER_IMAGE     := golangci/golangci-lint:v2.14.0
SHELLCHECK_IMAGE := koalaman/shellcheck:stable

# COMMANDS
CONTAINER_RUNNER := docker

## DATA

.PHONY: data
data:
	$(SCRIPTS_DIR)/fetch_data.sh $(RAW_DATA_DIR)

## FORMATTING

.PHONY: format_imports
format_imports:
	$(SCRIPTS_DIR)/format_imports.sh $(GENERATOR_DIR) $(GENERATOR_PKG)

.PHONY: format_golang
format_golang: format_imports
	$(SCRIPTS_DIR)/format_golang.sh $(GENERATOR_DIR)

.PHONY: format
format: format_golang

.PHONY: fmt
fmt: format

## LINTING

.PHONY: golang_lint
golang_lint:
	@$(SCRIPTS_DIR)/golang_lint.sh $(CONTAINER_RUNNER) $(LINTER_IMAGE) $(GENERATOR_DIR)

.PHONY: shellcheck
shellcheck:
	@$(SCRIPTS_DIR)/shellcheck.sh $(CONTAINER_RUNNER) $(SHELLCHECK_IMAGE) $(SCRIPTS_DIR)

.PHONY: lint
lint: golang_lint shellcheck

## EXECUTION

.PHONY: test
test:
	$(SCRIPTS_DIR)/test.sh $(GENERATOR_DIR)

# Pass generator flags through ARGS, e.g. make bank ARGS="-print -langs es".
.PHONY: bank
bank: data
	@$(SCRIPTS_DIR)/generate_bank.sh $(GENERATOR_DIR) $(RAW_DATA_DIR) $(BLOCKLIST_DIR) $(BANK_FILE) \
		-start $(BANK_START) -days $(BANK_DAYS) -seed $(BANK_SEED) $(ARGS)
