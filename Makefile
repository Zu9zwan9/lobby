APP     := Lobby
BUNDLE  := build/$(APP).app
BIN     := .build/release/$(APP)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# Override from the environment or a local .env that is not committed:
#   make notarize TEAM_ID=XXXXXXXXXX SIGN_ID="Developer ID Application: ..." KEYCHAIN_PROFILE=lobby
TEAM_ID          ?=
SIGN_ID          ?=
KEYCHAIN_PROFILE ?= lobby

.PHONY: all test check app icon sign notarize dmg clean

# Regenerates Resources/AppIcon.icns from Resources/makeicon.swift.
icon:
	xcrun swift Resources/makeicon.swift
	rm -rf /tmp/$(APP).iconset && mkdir -p /tmp/$(APP).iconset
	@for s in 16 32 128 256 512; do \
		sips -z $$s $$s Resources/icon-1024.png \
			--out /tmp/$(APP).iconset/icon_$${s}x$${s}.png >/dev/null; \
		d=$$((s*2)); \
		sips -z $$d $$d Resources/icon-1024.png \
			--out /tmp/$(APP).iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns /tmp/$(APP).iconset -o Resources/AppIcon.icns

all: test app

test:
	swift test

# Prints what Lobby sees on the current network. Exit 1 means action needed.
check:
	swift run -c release LobbyCheck

app: $(BIN)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	@[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/ || true
	@echo "built $(BUNDLE) ($(VERSION))"

$(BIN):
	swift build -c release --product $(APP)

# Hardened runtime is mandatory for notarization.
sign: app
	@test -n "$(SIGN_ID)" || (echo "set SIGN_ID"; exit 1)
	codesign --force --deep --options runtime --timestamp \
		--sign "$(SIGN_ID)" $(BUNDLE)
	codesign --verify --strict --verbose=2 $(BUNDLE)

dmg: sign
	rm -f build/$(APP)-$(VERSION).dmg
	hdiutil create -volname "$(APP)" -srcfolder $(BUNDLE) -ov -format UDZO \
		build/$(APP)-$(VERSION).dmg

# Two ways in, one target. Locally you store a credential profile once:
#   xcrun notarytool store-credentials lobby --apple-id ... --team-id ... --password <app-specific>
# In CI there is no keychain profile, so APPLE_ID/APPLE_APP_PASSWORD/TEAM_ID are
# passed instead. Keeping both behind one target means CI and your Mac cannot
# drift apart.
NOTARY_AUTH := $(if $(APPLE_ID),\
	--apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)" --password "$(APPLE_APP_PASSWORD)",\
	--keychain-profile "$(KEYCHAIN_PROFILE)")

notarize: dmg
	xcrun notarytool submit build/$(APP)-$(VERSION).dmg $(NOTARY_AUTH) --wait
	xcrun stapler staple build/$(APP)-$(VERSION).dmg
	@echo "notarized build/$(APP)-$(VERSION).dmg"

clean:
	rm -rf build .build
