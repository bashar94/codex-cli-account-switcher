#!/usr/bin/env bash
set -euo pipefail

# codex-accounts.sh — manage multiple Codex CLI accounts
# Storage layout:
#   Zips:   ~/codex-data/<account>.zip
#   State:  ~/.codex-switch/state   (CURRENT=..., PREVIOUS=...)

CODENAME="codex"
CODEX_HOME="${HOME}/.codex"
DATA_DIR="${HOME}/codex-data"
STATE_DIR="${HOME}/.codex-switch"
STATE_FILE="${STATE_DIR}/state"

# ------------- utils -------------
die() { echo "[ERR] $*" >&2; exit 1; }
note() { echo "[*] $*"; }
ok()  { echo "[OK] $*"; }

require_bin() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Install it first."
}

ensure_dirs() {
  mkdir -p "$DATA_DIR" "$STATE_DIR"
}

load_state() {
  CURRENT=""; PREVIOUS=""
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE" || true
  fi
}

save_state() {
  local cur="$1" prev="$2"
  printf "CURRENT=%q\nPREVIOUS=%q\n" "$cur" "$prev" > "$STATE_FILE"
}

zip_path_for() {
  local name="$1"
  echo "${DATA_DIR}/${name}.zip"
}

assert_codex_present_or_hint() {
  if [[ ! -d "$CODEX_HOME" ]]; then
    die "~/.codex not found. You likely haven't logged in yet.
Install Codex:  brew install codex
Then run:       ${CODENAME} login"
  fi
}

prompt_account_name() {
  local ans
  read -r -p "Enter a name for the CURRENT logged-in account (e.g., bashar, tazrin): " ans
  [[ -z "${ans:-}" ]] && die "Account name cannot be empty."
  echo "$ans"
}

backup_current_to() {
  # Requires ~/.codex to exist
  local name="$1"
  assert_codex_present_or_hint
  require_bin zip

  local tmpdir; tmpdir="$(mktemp -d)"
  local dest; dest="$(zip_path_for "$name")"

  note "Saving current ~/.codex to ${dest}..."
  # -RP: preserve symlinks without following them
  cp -RP "$CODEX_HOME" "${tmpdir}/.codex"
  # Remove tmp/ before zipping (temporary patch files, not worth saving)
  rm -rf "${tmpdir}/.codex/tmp"
  # Remove old archive (zip -r updates existing archives instead of replacing)
  rm -f "$dest"
  (
    cd "$tmpdir"
    # -y: store symlinks as symlinks (not their targets)
    zip -y -r -q "$dest" .codex
  )
  rm -rf "$tmpdir"
  local size; size="$(du -h "$dest" | cut -f1)"
  ok "Saved ${size}."
}

extract_to_codex() {
  local zipfile="$1"
  require_bin unzip

  [[ -f "$zipfile" ]] || die "Account archive not found: $zipfile"

  # Extract into a guaranteed-empty subdir to avoid conflicts with existing entries
  local tmpdir; tmpdir="$(mktemp -d)"
  local extractdir="${tmpdir}/extract"
  mkdir -p "$extractdir"

  note "Extracting $(basename "$zipfile")..."
  # -o: overwrite without prompting (safe since extractdir is empty)
  # This handles edge cases where zip has symlink + directory entries for same path
  unzip -o -q "$zipfile" -d "$extractdir"

  local extracted; extracted="$(find "$extractdir" -type d -name ".codex" | head -n1)"
  [[ -z "${extracted:-}" ]] && { rm -rf "$tmpdir"; die ".codex folder missing inside archive."; }

  rm -rf "$CODEX_HOME"
  mv "$extracted" "$CODEX_HOME"
  rm -rf "$tmpdir"
  ok "Activated archive into ~/.codex."
}

resolve_current_name_or_prompt() {
  # If CURRENT unknown but ~/.codex exists, ask user to name it so we can save it.
  load_state
  if [[ -z "${CURRENT:-}" && -d "$CODEX_HOME" ]]; then
    local named; named="$(prompt_account_name)"
    backup_current_to "$named"
    PREVIOUS=""        # No meaningful previous yet
    CURRENT="$named"
    save_state "$CURRENT" "$PREVIOUS"
  fi
}

# ------------- commands -------------
cmd_list() {
  ensure_dirs
  shopt -s nullglob
  local any=0
  for f in "$DATA_DIR"/*.zip; do
    any=1
    echo " - $(basename "${f%%.zip}" .zip)"
  done
  [[ $any -eq 0 ]] && echo "(no accounts saved yet)"
}

cmd_current() {
  load_state
  if [[ -n "${CURRENT:-}" ]]; then
    echo "Current:  $CURRENT"
  else
    echo "Current:  (unknown — no state recorded yet)"
  fi
  if [[ -n "${PREVIOUS:-}" ]]; then
    echo "Previous: $PREVIOUS"
  fi
}

cmd_save() {
  # Save the *currently logged-in* ~/.codex under a name
  ensure_dirs
  assert_codex_present_or_hint
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    name="$(prompt_account_name)"
  fi
  backup_current_to "$name"

  # Update CURRENT, leave PREVIOUS as-is if already set
  load_state
  PREVIOUS="${CURRENT:-}"
  CURRENT="$name"
  save_state "$CURRENT" "$PREVIOUS"
}

cmd_add() {
  # Add a NEW account slot:
  #  - If ~/.codex exists, back it up under CURRENT (or prompt for a name if unknown)
  #  - Clear ~/.codex so user can run `codex login` for the NEW name
  #  - Do NOT create the zip for the new one yet; that happens after they log in and run save/switch
  ensure_dirs
  resolve_current_name_or_prompt   # backs up & sets CURRENT if needed

  local newname="${1:-}"; [[ -z "$newname" ]] && die "Usage: $0 add <new-account-name>"

  if [[ -d "$CODEX_HOME" ]]; then
    note "Clearing ~/.codex to prepare login for '${newname}'..."
    rm -rf "$CODEX_HOME"
  fi
  ok "Ready. Now run: ${CODENAME} login  (to authenticate '${newname}')"
  echo "After login completes, run: $0 save ${newname}   (to store the new account)"
}

cmd_switch() {
  # Switch to an existing saved account by name:
  #  - Ensure the target zip exists
  #  - If ~/.codex exists, back it up under CURRENT (or prompt to name it)
  #  - Extract the target into ~/.codex
  local target="${1:-}"; [[ -z "$target" ]] && die "Usage: $0 switch <account-name>"

  ensure_dirs
  resolve_current_name_or_prompt   # may back up and set CURRENT if previously unknown

  local zipfile; zipfile="$(zip_path_for "$target")"
  [[ -f "$zipfile" ]] || die "No saved account named '${target}'. Use '$0 list' to see options."

  if [[ -d "$CODEX_HOME" ]]; then
    # Always back up current before switching
    load_state
    if [[ -z "${CURRENT:-}" ]]; then
      # Should not happen after resolve_current_name_or_prompt, but double-guard:
      CURRENT="$(prompt_account_name)"
    fi
    backup_current_to "$CURRENT"
  fi

  note "Switching to '${target}'..."
  extract_to_codex "$zipfile"

  # Update state
  load_state
  PREVIOUS="${CURRENT:-}"
  CURRENT="$target"
  save_state "$CURRENT" "$PREVIOUS"
  ok "Switched. Current account: ${CURRENT}"
}

cmd_help() {
  cat <<EOF
codex-accounts.sh — manage multiple Codex CLI accounts

USAGE
  $0 list
      Show all saved accounts (from ${DATA_DIR}).

  $0 current
      Show current and previous accounts from the state.

  $0 save [<name>]
      Zip the current ~/.codex into ${DATA_DIR}/<name>.zip.
      If <name> is omitted, you'll be prompted.

  $0 add <name>
      Prepare to add a new account:
        - backs up current (prompting for its name if unknown),
        - clears ~/.codex so you can run 'codex login',
        - after login, run: $0 save <name>

  $0 switch <name>
      Switch to an existing saved account (name is mandatory).
      Backs up current first, then activates <name>.

NOTES
  - Requires 'zip' and 'unzip'.
  - If ~/.codex is missing when saving/adding, you'll be prompted to login first.
  - Install Codex if needed:  brew install codex
EOF
}

# ------------- main -------------
main() {
  require_bin zip
  require_bin unzip
  ensure_dirs

  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    list)    cmd_list "$@";;
    current) cmd_current "$@";;
    save)    cmd_save "$@";;
    add)     cmd_add "$@";;
    switch)  cmd_switch "$@";;
    help|--help|-h) cmd_help;;
    *) die "Unknown command: $cmd. See '$0 help'.";;
  esac
}

main "$@"
