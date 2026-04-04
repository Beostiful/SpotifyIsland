APP_NAME = SpotifyIsland
INSTALL_DIR = $(HOME)/Applications
APP_BUNDLE = $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: build install run clean

build:
	swift build -c release

install: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp .build/release/$(APP_NAME) "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp SpotifyIsland/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@# Register URL scheme with LaunchServices
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(APP_BUNDLE)"
	@echo "Installed to $(APP_BUNDLE)"

run: install
	@pkill -f $(APP_NAME) 2>/dev/null; sleep 0.5; true
	open "$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf .build
