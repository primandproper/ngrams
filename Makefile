# PATHS
GENERATOR_DIR := generator
GENERATOR_PKG := github.com/verygoodsoftwarenotvirus/ngrams/$(GENERATOR_DIR)
SCRIPTS_DIR   := scripts
RAW_DATA_DIR  := data/raw
BLOCKLIST_DIR := data/blocklists

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

# Pass prototype flags through ARGS, e.g. make tiles-prototype ARGS="-langs es -ns 4".
.PHONY: tiles-prototype
tiles-prototype: data
	@$(SCRIPTS_DIR)/tiles_prototype.sh $(GENERATOR_DIR) $(RAW_DATA_DIR) $(BLOCKLIST_DIR) $(ARGS)
