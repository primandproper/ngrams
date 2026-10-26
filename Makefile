# PATHS
GENERATOR_DIR := generator
GENERATOR_PKG := github.com/primandproper/ngrams/$(GENERATOR_DIR)
IOS_DIR       := ios
SCRIPTS_DIR   := scripts
RAW_DATA_DIR  := data/raw
BLOCKLIST_DIR := data/blocklists
BANK_FILE     := data/bank/puzzles.json
GUESS_DIR     := data/bank/guesses

# BANK
# The committed bank starts here. Moving the start or seed regenerates every board.
BANK_START := 2026-10-23
BANK_DAYS  := 90
BANK_SEED  := 1

# RELEASE
# App Store Connect API key; the .p8 itself lives in 1Password under ASC_KEY_ITEM.
ASC_KEY_ID     := 9ZW28F2324
ASC_ISSUER_ID  := ddeb2389-f4e3-4804-a04e-4b5fd77b1a4e
ASC_KEY_ITEM   := hd444byt2soiz5hivq2rx6twqy
MIN_BANK_DAYS  := 60

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

.PHONY: format_swift
format_swift:
	$(SCRIPTS_DIR)/format_swift.sh $(IOS_DIR)

.PHONY: format
format: format_golang format_swift

.PHONY: fmt
fmt: format

## LINTING

.PHONY: golang_lint
golang_lint:
	@$(SCRIPTS_DIR)/golang_lint.sh $(CONTAINER_RUNNER) $(LINTER_IMAGE) $(GENERATOR_DIR)

.PHONY: shellcheck
shellcheck:
	@$(SCRIPTS_DIR)/shellcheck.sh $(CONTAINER_RUNNER) $(SHELLCHECK_IMAGE) $(SCRIPTS_DIR)

.PHONY: swift_lint
swift_lint:
	@$(SCRIPTS_DIR)/lint_swift.sh $(IOS_DIR)

.PHONY: lint
lint: golang_lint shellcheck swift_lint

## EXECUTION

.PHONY: test_golang
test_golang:
	$(SCRIPTS_DIR)/test.sh $(GENERATOR_DIR)

# Override the simulator with IOS_SIM="iPhone 18 Pro Max".
.PHONY: test_ios
test_ios:
	$(SCRIPTS_DIR)/test_ios.sh $(IOS_DIR)

.PHONY: test
test: test_golang test_ios

# Installs a Debug build on the paired iPhone. Pick one with IOS_DEVICE="Jeffrey’s iPhone".
.PHONY: ios_install
ios_install:
	$(SCRIPTS_DIR)/install_ios.sh $(IOS_DIR)

# Redraws the app icon's variants into the asset catalog.
.PHONY: icon
icon:
	$(SCRIPTS_DIR)/make_icon.sh $(IOS_DIR)

# Pass generator flags through ARGS, e.g. make bank ARGS="-print -langs es".
.PHONY: bank
bank: data
	@$(SCRIPTS_DIR)/generate_bank.sh $(GENERATOR_DIR) $(RAW_DATA_DIR) $(BLOCKLIST_DIR) $(BANK_FILE) $(GUESS_DIR) \
		-start $(BANK_START) -days $(BANK_DAYS) -seed $(BANK_SEED) $(ARGS)

## RELEASE

# Uploads a Release build to App Store Connect and tags it. Submit and release it there by hand.
.PHONY: release
release:
	@$(SCRIPTS_DIR)/release.sh $(IOS_DIR) $(BANK_FILE) $(ASC_KEY_ID) $(ASC_ISSUER_ID) $(ASC_KEY_ITEM) $(MIN_BANK_DAYS)
