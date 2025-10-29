# Codex Accounts Switcher 🌀

**Easily manage multiple OpenAI Codex CLI accounts — switch, save, and restore with one command.**

The official [OpenAI Codex CLI](https://github.com/openai/codex) does **not support multi-account login**.  
Users must manually swap `~/.codex` folders or re-authenticate every time they switch accounts — a painful process for developers who use multiple OpenAI accounts (for example, personal vs work).

I raised this issue here: [#4432](https://github.com/openai/codex/issues/4432)  
and also created a pull request adding multi-account support: [#4457](https://github.com/openai/codex/pull/4457)  
However, the feature hasn’t yet been merged or prioritized, so this standalone script fills that gap.

***I HAVE TESTED THIS ON MAC ONLY***


---

## 🔧 Installation

```bash
# Clone and install
git clone https://github.com/bashar94/codex-cli-account-switcher.git
cd codex-accounts-switcher
chmod +x codex-accounts.sh

# Optionally make it global
sudo mv codex-accounts.sh /usr/local/bin/codex-accounts
```

## 🚀 Usage
```
codex-accounts list
codex-accounts current
codex-accounts save <name>
codex-accounts add <name>
codex-accounts switch <name>
```
### Examples
```
# Save your current login
codex-accounts save bashar

# Add a new account slot
codex-accounts add tazrin
codex login   # then run:
codex-accounts save tazrin

# Switch between accounts
codex-accounts switch bashar
```
## 📁 Data Locations
Codex stores its session data inside `~/.codex`.
This script backs up each account’s `.codex` directory as a compressed zip file and lets you swap them instantly.

| Path                      | Purpose                              |
| ------------------------- | ------------------------------------ |
| `~/.codex`                | Active Codex session folder          |
| `~/codex-data/<name>.zip` | Saved account backups                |
| `~/.codex-switch/state`   | Tracks current and previous accounts |

It’s safe to use — your Codex configuration is preserved before every switch.

## ⚙️ Requirements
- macOS / Linux
- `zip`, `unzip`, `bash`
- Codex CLI installed:
  - macOS: `brew install codex`
  - Linux: use your package manager or follow the [Codex CLI docs](https://developers.openai.com/codex/cli/)

## 🧠 Notes
- Supports unlimited accounts — name-based switching.
- Automatically backs up the current account before changing.
- Shows the current and previous account states.
- Works cross-platform: macOS, Linux, WSL.
- Simple shell-only dependencies (`bash`, `zip`, `unzip`).
- Helpful prompts if Codex isn’t installed or logged in yet.
- You can safely share this across machines (just copy `~/codex-data`).
