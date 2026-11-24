# Copilot Meter

A native macOS menu bar app that shows how much of your GitHub Copilot plan quota you have used, as one percentage.

## Requirements

- macOS 13 or newer
- Swift 6
- A recent [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/install-copilot-cli) signed in to the account you want to monitor

## Install

```bash
copilot login # skip if already signed in
make install
```

`make install` installs and starts `~/Applications/CopilotMeter.app` and registers it to run at login. It records the Copilot CLI path so the menu bar app can find it without a terminal. Rerun `make install` if the CLI moves.

## Usage

`24%` means 24% used, not 24% remaining. The meter refreshes every five minutes. Its menu shows the last update, offers **Refresh Now**, and explains why if the bar shows `—`.

## Data source and limitations

The meter starts Copilot CLI briefly to read the active account's `premium_interactions` plan quota through the Copilot SDK's experimental `account.getQuota` RPC. It does not send prompts, request extra OAuth scopes, or store tokens or quota settings. The percentage is for the plan, not Copilot's separate session or weekly rate limits. If the CLI RPC changes, the meter may need an update.

## Develop

```bash
make test
make build
```

The signed ad-hoc app bundle is generated at `dist/CopilotMeter.app`. To read the same value without opening the menu bar app, run `dist/CopilotMeter.app/Contents/MacOS/CopilotMeter --quota`.
