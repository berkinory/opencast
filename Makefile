.DEFAULT_GOAL := check

SHELL := /bin/bash

PROJECT := Opencast.xcodeproj
SCHEME := Opencast
CONFIGURATION ?= Debug
DERIVED_DATA ?= build/DerivedData
TEST_BIN_DIR := build/tests
SWIFT_FORMAT ?= swift-format
CODE_SIGNING_ALLOWED ?= NO

SWIFT_FILES := $(shell find Opencast Tools -type f -name '*.swift' ! -name '*generated.swift' -print)

.PHONY: check tools format lint build run release unsigned-dmg test extensions-test extension-provider-test extension-host-build extension-store-test extension-budget-test generate clean

check: lint test build

tools:
	@command -v "$(SWIFT_FORMAT)" >/dev/null || { echo "error: $(SWIFT_FORMAT) is required" >&2; exit 1; }
	@command -v swift >/dev/null || { echo "error: swift is required" >&2; exit 1; }
	@command -v swiftc >/dev/null || { echo "error: swiftc is required" >&2; exit 1; }
	@command -v xcodebuild >/dev/null || { echo "error: xcodebuild is required" >&2; exit 1; }

format: tools
	$(SWIFT_FORMAT) format --in-place --configuration .swift-format.json $(SWIFT_FILES)

lint: tools
	$(SWIFT_FORMAT) lint --strict --configuration .swift-format.json $(SWIFT_FILES)

build: tools
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=$(CODE_SIGNING_ALLOWED) build

run: CONFIGURATION=Debug
run: build
	@killall "Opencast Dev" 2>/dev/null || true
	@while pgrep -x "Opencast Dev" >/dev/null; do sleep 0.1; done
	open -n "$(DERIVED_DATA)/Build/Products/Debug/Opencast Dev.app"

release:
	./build-dmg.sh

unsigned-dmg:
	SKIP_SIGNING=1 ./build-dmg.sh

test: tools
	@mkdir -p $(TEST_BIN_DIR)
	cp Tools/fuzz-test.swift $(TEST_BIN_DIR)/main.swift
	swiftc -swift-version 6 Opencast/Features/Launcher/Romanization.swift $(TEST_BIN_DIR)/main.swift -o $(TEST_BIN_DIR)/fuzz-test
	$(TEST_BIN_DIR)/fuzz-test
	swiftc -swift-version 6 Opencast/Features/Settings/SettingsSearchIndex.swift Tools/settings-search-test.swift -o $(TEST_BIN_DIR)/settings-search-test
	$(TEST_BIN_DIR)/settings-search-test
	swiftc -swift-version 6 Opencast/Features/Launcher/LauncherRankingStore.swift Tools/ranking-test.swift -o $(TEST_BIN_DIR)/ranking-test
	$(TEST_BIN_DIR)/ranking-test
	swiftc -swift-version 6 Opencast/Features/Launcher/SearchScopes.swift Tools/scopes-test.swift -o $(TEST_BIN_DIR)/scopes-test
	$(TEST_BIN_DIR)/scopes-test
	swiftc Opencast/Features/Calculator/Engine/*.swift Tools/calc-test.swift -o $(TEST_BIN_DIR)/calc-test
	$(TEST_BIN_DIR)/calc-test
	swiftc -swift-version 6 Opencast/Features/Clipboard/ClipboardStore.swift Tools/clipboard-test.swift -o $(TEST_BIN_DIR)/clipboard-test
	$(TEST_BIN_DIR)/clipboard-test
	swiftc Opencast/Features/Emoji/EmojiCatalog.swift Opencast/Features/Emoji/EmojiData.generated.swift Tools/emoji-test.swift -o $(TEST_BIN_DIR)/emoji-test
	$(TEST_BIN_DIR)/emoji-test
	swiftc -swift-version 6 Opencast/Features/Palette/PaletteGridGeometry.swift Tools/palette-grid-test.swift -o $(TEST_BIN_DIR)/palette-grid-test
	$(TEST_BIN_DIR)/palette-grid-test
	swiftc -swift-version 6 Opencast/Features/SystemCommands/SystemCommand.swift Tools/system-command-test.swift -o $(TEST_BIN_DIR)/system-command-test
	$(TEST_BIN_DIR)/system-command-test
	swiftc -swift-version 6 \
		Opencast/Features/WindowManagement/WindowCommand.swift \
		Opencast/Features/WindowManagement/WindowLayout.swift \
		Opencast/Features/WindowManagement/WindowActionMemory.swift \
		Tools/window-command-test.swift -o $(TEST_BIN_DIR)/window-command-test
	$(TEST_BIN_DIR)/window-command-test
	swiftc -swift-version 6 Opencast/Features/HotKeys/DoubleCommandDetector.swift Tools/hotkey-test.swift -o $(TEST_BIN_DIR)/hotkey-test
	$(TEST_BIN_DIR)/hotkey-test
	swiftc -swift-version 6 Opencast/Features/Uninstall/AppLeftovers.swift Tools/uninstall-test.swift -o $(TEST_BIN_DIR)/uninstall-test
	$(TEST_BIN_DIR)/uninstall-test

extensions-test: extension-host-build
	@command -v node >/dev/null || { echo "error: node is required" >&2; exit 1; }
	@command -v bun >/dev/null || { echo "error: bun is required" >&2; exit 1; }
	rm -rf build/extensions
	node Tools/extensions/build-extension.js --package Extensions/Packages/kill-process --out build/extensions/kill-process.ocx
	node Tools/extensions/build-extension.js --package Extensions/Packages/port-manager --out build/extensions/port-manager.ocx
	node Tools/extensions/build-extension.js --package Extensions/Packages/system-monitor --out build/extensions/system-monitor.ocx
	node Tools/extensions/host-contract-test.js
	$(MAKE) extension-provider-test

extension-provider-test: tools
	@mkdir -p $(TEST_BIN_DIR)
	swiftc -swift-version 6 \
		Opencast/Features/Extensions/ExtensionSystemCommand.swift \
		Opencast/Features/Extensions/ExtensionProcessProvider.swift \
		Opencast/Features/Extensions/ExtensionPortProvider.swift \
		Opencast/Features/Extensions/ExtensionSystemMetricsProvider.swift \
		Opencast/Features/Extensions/ExtensionProcessJobManager.swift \
		Tools/extensions/provider-test.swift \
		-o $(TEST_BIN_DIR)/extension-provider-test
	$(TEST_BIN_DIR)/extension-provider-test

extension-host-build:
	xcodebuild -project $(PROJECT) -scheme OpencastExtensionHost -configuration Debug -derivedDataPath build/ExtensionHostDerived CODE_SIGNING_ALLOWED=NO build

extension-store-test: extension-host-build
	rm -rf build/extensions
	node Tools/extensions/build-extension.js --package Extensions/Packages/kill-process --out build/extensions/kill-process.ocx
	node Tools/extensions/build-extension.js --package Extensions/Packages/port-manager --out build/extensions/port-manager.ocx
	node Tools/extensions/build-extension.js --package Extensions/Packages/system-monitor --out build/extensions/system-monitor.ocx
	@mkdir -p $(TEST_BIN_DIR)
	cp Tools/extensions/store-test.swift $(TEST_BIN_DIR)/main.swift
	swiftc -swift-version 6 Opencast/Features/Extensions/ExtensionModels.swift Opencast/Features/Extensions/ExtensionPackageValidator.swift $(TEST_BIN_DIR)/main.swift -o $(TEST_BIN_DIR)/extension-store-test
	$(TEST_BIN_DIR)/extension-store-test build/extensions/kill-process.ocx
	$(TEST_BIN_DIR)/extension-store-test build/extensions/port-manager.ocx
	$(TEST_BIN_DIR)/extension-store-test build/extensions/system-monitor.ocx

extension-budget-test:
	@command -v node >/dev/null || { echo "error: node is required" >&2; exit 1; }
	node Tools/extensions/budget-test.js

generate:
	@command -v xcodegen >/dev/null || { echo "error: xcodegen is required" >&2; exit 1; }
	xcodegen generate

clean:
	rm -rf $(DERIVED_DATA) build/ExtensionHostDerived build/extensions $(TEST_BIN_DIR)
