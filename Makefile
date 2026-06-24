PROJECT := Aquarium.xcodeproj
SCHEME := Aquarium
CONFIGURATION ?= Debug
VERSION ?= 0.1.10
DERIVED_DATA := .build/DerivedData
ARCHIVE_PATH := .build/Aquarium.xcarchive
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/Aquarium.app
RELEASE_APP_PATH := $(DERIVED_DATA)/Build/Products/Release/Aquarium.app
HELPER_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/aquarium-helper
PACKAGE_DIR := .build/package
RELEASE_ZIP := .build/Aquarium-$(VERSION).zip

.PHONY: generate build release package clean archive install-helper uninstall-helper open

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) build

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED_DATA) build

package: release
	rm -rf "$(PACKAGE_DIR)" "$(RELEASE_ZIP)"
	mkdir -p "$(PACKAGE_DIR)"
	cp -R "$(RELEASE_APP_PATH)" "$(PACKAGE_DIR)/Aquarium.app"
	ditto -c -k --keepParent "$(PACKAGE_DIR)/Aquarium.app" "$(RELEASE_ZIP)"
	@echo "Created $(RELEASE_ZIP)"

archive: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -archivePath $(ARCHIVE_PATH) archive

install-helper: build
	sudo install -d -m 755 "/Library/PrivilegedHelperTools"
	sudo install -m 755 "$(HELPER_PATH)" "/Library/PrivilegedHelperTools/com.aquarium.helper"
	sudo install -d -m 775 -o root -g staff "/Library/Application Support/Aquarium"
	[ -f "/Library/Application Support/Aquarium/config.json" ] || sudo install -m 664 -o root -g staff "Resources/AquariumHelper/default-config.json" "/Library/Application Support/Aquarium/config.json"
	sudo install -m 644 "Resources/AquariumHelper/com.aquarium.helper.plist" "/Library/LaunchDaemons/com.aquarium.helper.plist"
	sudo launchctl bootout system /Library/LaunchDaemons/com.aquarium.helper.plist 2>/dev/null || true
	sudo launchctl bootstrap system /Library/LaunchDaemons/com.aquarium.helper.plist
	sudo launchctl enable system/com.aquarium.helper

uninstall-helper:
	sudo launchctl bootout system /Library/LaunchDaemons/com.aquarium.helper.plist 2>/dev/null || true
	sudo rm -f /Library/LaunchDaemons/com.aquarium.helper.plist
	sudo rm -f /Library/PrivilegedHelperTools/com.aquarium.helper

open: build
	open "$(APP_PATH)"

clean:
	rm -rf .build $(PROJECT)
