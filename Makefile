APP_NAME := Clarion
BUILD_DIR := .build
BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
BINARY := $(BUILD_DIR)/release/$(APP_NAME)
INSTALL_DIR := /Applications

.PHONY: build bundle run install clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(BUNDLE)/Contents/
	cp Resources/*.html Resources/*.css $(BUNDLE)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign - --entitlements Resources/Clarion.entitlements $(BUNDLE)

run: bundle
	open $(BUNDLE)

install: bundle
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(BUNDLE) $(INSTALL_DIR)/$(APP_NAME).app
	/System/Library/CoreServices/pbs -flush

clean:
	swift package clean
	rm -rf $(BUNDLE)
