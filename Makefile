.PHONY: build test install

LABEL := com.ozanmanav.CopilotMeter
APP := CopilotMeter.app

build:
	@swift build -c release
	@mkdir -p "dist/$(APP)/Contents/MacOS"
	@cp .build/release/CopilotMeter "dist/$(APP)/Contents/MacOS/CopilotMeter"
	@cp Resources/Info.plist "dist/$(APP)/Contents/Info.plist"
	@codesign --force --sign - "dist/$(APP)"

test:
	@macro="$$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"; \
	if [ -f "$$macro" ]; then \
		swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$$macro"; \
	else \
		swift test --disable-xctest; \
	fi

install: build
	@set -eu; \
	cli="$${COPILOT_METER_CLI:-$${COPILOT_CLI_PATH:-}}"; \
	if [ -z "$$cli" ]; then \
		cli="$$(command -v copilot)" || { echo 'Install Copilot CLI first.' >&2; exit 1; }; \
	fi; \
	if [ ! -x "$$cli" ]; then echo "Copilot CLI is not executable: $$cli" >&2; exit 1; fi; \
	path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"; \
	if node="$$(command -v node)"; then path="$$(dirname "$$node"):$$path"; fi; \
	app="$$HOME/Applications/$(APP)"; \
	agent="$$HOME/Library/LaunchAgents/$(LABEL).plist"; \
	domain="gui/$$(id -u)"; \
	mkdir -p "$$HOME/Applications" "$$HOME/Library/LaunchAgents"; \
	if launchctl print "$$domain/$(LABEL)" >/dev/null 2>&1; then \
		launchctl bootout "$$domain/$(LABEL)"; \
	fi; \
	ditto "dist/$(APP)" "$$app"; \
	cp Resources/LaunchAgent.plist "$$agent"; \
	plutil -replace Program -string "$$app/Contents/MacOS/CopilotMeter" "$$agent"; \
	plutil -insert EnvironmentVariables.COPILOT_METER_CLI -string "$$cli" "$$agent"; \
	plutil -insert EnvironmentVariables.PATH -string "$$path" "$$agent"; \
	if [ -n "$${COPILOT_METER_HOST:-}" ]; then \
		plutil -insert EnvironmentVariables.COPILOT_METER_HOST -string "$$COPILOT_METER_HOST" "$$agent"; \
	fi; \
	launchctl bootstrap "$$domain" "$$agent"
