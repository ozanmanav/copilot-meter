.PHONY: build test install auth

build:
	@swift build -c release
	@mkdir -p dist/CopilotMeter.app/Contents/MacOS
	@cp .build/release/CopilotMeter dist/CopilotMeter.app/Contents/MacOS/CopilotMeter
	@cp Resources/Info.plist dist/CopilotMeter.app/Contents/Info.plist
	@codesign --force --sign - dist/CopilotMeter.app

test:
	@swift test

install: build
	@mkdir -p "$$HOME/Applications" "$$HOME/Library/LaunchAgents"
	@rm -rf "$$HOME/Applications/CopilotMeter.app"
	@cp -R dist/CopilotMeter.app "$$HOME/Applications/CopilotMeter.app"
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>Label</key>' \
		'  <string>com.ozanmanav.CopilotMeter</string>' \
		'  <key>ProgramArguments</key>' \
		'  <array><string>'"$$HOME"'/Applications/CopilotMeter.app/Contents/MacOS/CopilotMeter</string></array>' \
		'  <key>RunAtLoad</key><true/>' \
		'  <key>KeepAlive</key><true/>' \
		'</dict>' \
		'</plist>' > "$$HOME/Library/LaunchAgents/com.ozanmanav.CopilotMeter.plist"
	@launchctl bootout "gui/$$(id -u)" "$$HOME/Library/LaunchAgents/com.ozanmanav.CopilotMeter.plist" 2>/dev/null || true
	@launchctl bootstrap "gui/$$(id -u)" "$$HOME/Library/LaunchAgents/com.ozanmanav.CopilotMeter.plist"

auth:
	@gh auth refresh -h github.com -s user
