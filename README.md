# Copilot Meter

A lightweight macOS menu bar app that displays the current month's GitHub Copilot AI credit usage as one percentage.

## Requirements

- macOS 13 or newer
- Swift 6
- GitHub CLI (`gh`)

## Install

```bash
gh auth login -h github.com
gh auth refresh -h github.com -s user
make install
```

`make install` creates `~/Applications/CopilotMeter.app` and starts it after login through a LaunchAgent.

The GitHub OAuth `user` scope is required because the usage endpoint is under GitHub's billing API. The scope is used by `gh`; Copilot Meter does not store or request tokens itself.

## Usage

The menu bar shows a single value such as `24%`. Click it to:

- see used and available AI credits;
- refresh immediately;
- set the monthly allowance;
- open GitHub usage details; or
- quit.

Copilot Meter refreshes every five minutes. It defaults to 1,500 monthly AI credits (the current total shown for Copilot Pro including its flex allotment). Set the value from the menu if the account uses another plan:

| Plan | Monthly AI credits |
| --- | ---: |
| Copilot Pro | 1,500 |
| Copilot Pro+ | 7,000 |
| Copilot Max | 20,000 |

## Data source and limitations

Copilot Meter reads `GET /users/{username}/settings/billing/ai_credit/usage` from GitHub's REST API. GitHub returns usage billed directly to the signed-in personal account. Usage from a Copilot license billed through an organization or enterprise is not included in this user-level endpoint.

## Develop

```bash
make test
make build
```

The signed ad-hoc app bundle is generated at `dist/CopilotMeter.app`.
