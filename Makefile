APP      := ClaudeMultiUsage
BUNDLE   := $(APP).app
BINARY   := .build/release/$(APP)

# Codesigning identity. Defaults to ad-hoc ("-") so the project builds with no
# Apple Developer account. For local development, override with your own stable
# identity so the signature stays constant across rebuilds, e.g.:
#   make run IDENTITY="Apple Development: Your Name (TEAMID)"
# or export IDENTITY in your shell.
IDENTITY ?= -

.PHONY: build bundle run clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	cp -R .build/release/$(APP)_$(APP).bundle $(BUNDLE)/Contents/Resources/
	codesign --force --deep --sign "$(IDENTITY)" $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: bundle
	@pkill -f "$(BUNDLE)/Contents/MacOS/$(APP)" 2>/dev/null || true
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
