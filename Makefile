# PATHS
GENERATOR_DIR := generator
GENERATOR_PKG := github.com/primandproper/ngrams/$(GENERATOR_DIR)
IOS_DIR       := ios
ANDROID_DIR   := android
SCRIPTS_DIR   := scripts
RAW_DATA_DIR  := data/raw
BLOCKLIST_DIR := data/blocklists
BANK_FILE     := data/bank/puzzles.json
GUESS_DIR     := data/bank/guesses
SCREENSHOTS   := ios/build/screenshots
# The interface language the store screenshots are captured in: en or es.
SCREENSHOT_LANGUAGE ?= en
PLAY_ASSETS   := android/build/play
HEADER        := ios/build/app-store/header.png

# BANK
# The committed bank starts here. Moving the start or seed regenerates every board.
BANK_START := 2026-10-23
BANK_DAYS  := 260
BANK_SEED  := 1

# RELEASE
# App Store Connect API key; the .p8 itself lives in 1Password under ASC_KEY_ITEM.
ASC_KEY_ID     := YKYV3KLQVJ
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

.PHONY: format_kotlin
format_kotlin:
	$(SCRIPTS_DIR)/format_kotlin.sh $(ANDROID_DIR)

.PHONY: format
format: format_golang format_swift format_kotlin

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

# Fails on iOS text with no Spanish translation.
.PHONY: ios_strings_lint
ios_strings_lint:
	@$(SCRIPTS_DIR)/lint_strings_ios.sh $(IOS_DIR)

.PHONY: kotlin_lint
kotlin_lint:
	@$(SCRIPTS_DIR)/lint_kotlin.sh $(ANDROID_DIR)

# Fails on Android text with no Spanish translation.
.PHONY: android_strings_lint
android_strings_lint:
	@$(SCRIPTS_DIR)/lint_strings_android.sh $(ANDROID_DIR)

.PHONY: lint
lint: golang_lint shellcheck swift_lint ios_strings_lint kotlin_lint android_strings_lint

## EXECUTION

.PHONY: test_golang
test_golang:
	$(SCRIPTS_DIR)/test.sh $(GENERATOR_DIR)

# Override the simulator with IOS_SIM="iPhone 18 Pro Max".
.PHONY: test_ios
test_ios:
	$(SCRIPTS_DIR)/test_ios.sh $(IOS_DIR)

.PHONY: test_android
test_android:
	$(SCRIPTS_DIR)/test_android.sh $(ANDROID_DIR)

.PHONY: test
test: test_golang test_ios test_android

# Installs a Debug build on the paired iPhone. Pick one with IOS_DEVICE="Jeffrey’s iPhone".
.PHONY: ios_install
ios_install:
	$(SCRIPTS_DIR)/install_ios.sh $(IOS_DIR)

# Opens a Debug build on a Pixel 8 emulator, booting one in a window first if none is up.
.PHONY: android_run
android_run:
	$(SCRIPTS_DIR)/run_android.sh $(ANDROID_DIR)

# Redraws the app icon: the iOS asset catalog's variants and the Android adaptive icon's layers.
.PHONY: icon
icon:
	$(SCRIPTS_DIR)/make_icon.sh $(IOS_DIR) $(ANDROID_DIR)

# Pass generator flags through ARGS, e.g. make bank ARGS="-print -langs es".
.PHONY: bank
bank: data
	@$(SCRIPTS_DIR)/generate_bank.sh $(GENERATOR_DIR) $(RAW_DATA_DIR) $(BLOCKLIST_DIR) $(BANK_FILE) $(GUESS_DIR) \
		-start $(BANK_START) -days $(BANK_DAYS) -seed $(BANK_SEED) $(ARGS)

## RELEASE

.PHONY: screenshots
screenshots: screenshots_ios screenshots_android

# Captures the App Store screenshots in SCREENSHOT_LANGUAGE into a folder per display size under
# SCREENSHOTS/<language>. Medium (1206x2622) is the size App Store Connect requires; large
# (1320x2868) is optional.
.PHONY: screenshots_ios
screenshots_ios:
	$(SCRIPTS_DIR)/screenshots.sh $(IOS_DIR) $(SCREENSHOTS)/$(SCREENSHOT_LANGUAGE)/medium "iPhone 18 Pro" $(SCREENSHOT_LANGUAGE)
	$(SCRIPTS_DIR)/screenshots.sh $(IOS_DIR) $(SCREENSHOTS)/$(SCREENSHOT_LANGUAGE)/large "iPhone 18 Pro Max" $(SCREENSHOT_LANGUAGE)

# Captures the Play Store phone screenshots (1080x1920) in SCREENSHOT_LANGUAGE into
# PLAY_ASSETS/screenshots/<language>.
.PHONY: screenshots_android
screenshots_android:
	$(SCRIPTS_DIR)/screenshots_android.sh $(ANDROID_DIR) $(PLAY_ASSETS)/screenshots/$(SCREENSHOT_LANGUAGE) $(SCREENSHOT_LANGUAGE)

# Draws the store banners: the App Store header into HEADER and the Play feature graphic into
# PLAY_ASSETS.
.PHONY: header
header:
	$(SCRIPTS_DIR)/make_header.sh $(IOS_DIR) $(HEADER) $(PLAY_ASSETS)/feature-graphic.png

# Uploads a Release build to App Store Connect and tags it. Submit and release it there by hand.
.PHONY: release
release:
	@$(SCRIPTS_DIR)/release.sh $(IOS_DIR) $(BANK_FILE) $(ASC_KEY_ID) $(ASC_ISSUER_ID) $(ASC_KEY_ITEM) $(MIN_BANK_DAYS)
