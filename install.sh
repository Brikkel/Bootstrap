#!/bin/sh
# Bootstrap a new machine with Rik's dotfiles (chezmoi). On the new machine:
#   curl -fsSL https://raw.githubusercontent.com/Brikkel/Bootstrap/main/install.sh | sh
#
# 1. installs git + chezmoi (Homebrew on macOS, pacman on Arch, apt on Debian/Raspberry Pi OS)
# 2. asks whether it's a work machine and its short name
# 3. creates this machine's SSH key (~/.ssh/<machine>) and waits until you've added it:
#      personal: to your GitLab account, dotfiles come from gitlab.brikkel.com (home network / WireGuard)
#      work:     as deploy keys only (GitHub mirror read-only, work-notes with write access)
# 4. runs chezmoi init --apply, which asks the remaining questions
#
# Safe to run again (after Ctrl-C or a wrong answer): the key and ssh config are kept, and it offers to
# answer chezmoi's questions again.
# Source of truth: install.sh in the dotfiles repo; the public Brikkel/Bootstrap repo holds a copy.
# Testing: BOOTSTRAP_NONINTERACTIVE=1 MACHINE=x WORK=false DOTFILES_REPO=<path or url> sh install.sh
set -eu

GITLAB=gitlab.brikkel.com
PERSONAL_REPO="git@$GITLAB:brikkel/dotfiles.git"
WORK_REPO="git@github-dotfiles:Brikkel/dotfiles.git" # ssh alias below: github.com with this machine's deploy key
NONINTERACTIVE="${BOOTSTRAP_NONINTERACTIVE:-}"

say()  { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
ask()  { # ask <question> <default>: answer in $REPLY
  if [ -n "$NONINTERACTIVE" ]; then REPLY="$2"; return; fi
  printf '    %s [%s] ' "$1" "$2" >/dev/tty
  read -r REPLY </dev/tty || true
  [ -n "$REPLY" ] || REPLY="$2"
}
tty_in() { if [ -n "$NONINTERACTIVE" ]; then "$@" </dev/null; else "$@" </dev/tty; fi; }

# --- 1. git + chezmoi --------------------------------------------------------------------------
say "Installing git + chezmoi"
os="$(uname -s)"
case "$os" in
  Darwin)
    if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
      tty_in /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
    brew install git chezmoi
    ;;
  Linux)
    . /etc/os-release
    case "$ID" in
      arch)
        sudo pacman -Syu --needed --noconfirm git chezmoi openssh ;;
      debian|ubuntu|raspbian)
        sudo apt-get update && sudo apt-get install -y git curl openssh-client
        if ! command -v chezmoi >/dev/null 2>&1; then
          sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
        fi
        PATH="$HOME/.local/bin:$PATH" ;;
      *) echo "install.sh: unsupported Linux ($ID)" >&2; exit 1 ;;
    esac
    ;;
  *) echo "install.sh: unsupported OS ($os)" >&2; exit 1 ;;
esac

# --- 2. questions --------------------------------------------------------------------------------
say "About this machine"
default_machine="$(uname -n | cut -d. -f1 | tr 'A-Z' 'a-z')" # `hostname` isn't on a minimal Arch
note "Type the answer and press Enter; Enter alone takes the default in [brackets]."
case "${WORK:-false}" in true) default_work=y ;; *) default_work=n ;; esac
ask "Work machine? (y/n)" "$default_work"
case "$REPLY" in y*|Y*|true) work=true ;; *) work=false ;; esac
if [ "$work" = true ]; then
  note "Short name for the dotfiles (WireGuard peer, host lists), e.g. mbp-work."
  note "Not the SUE computer name: chezmoi asks the SUE item id later and sets that name itself."
else
  note "Short name for the dotfiles (WireGuard peer, host lists); Finding Nemo names, e.g. squirt."
fi
ask "Machine name:" "${MACHINE:-$default_machine}"
machine="$REPLY"

# --- 3. SSH key ---------------------------------------------------------------------------------
key="$HOME/.ssh/$machine"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$key" ]; then
  say "Creating SSH key $key"
  note "A passphrase is optional (macOS keeps it in the Keychain)."
  if [ -n "$NONINTERACTIVE" ]; then
    ssh-keygen -q -t ed25519 -C "$machine" -f "$key" -N ""
  else
    tty_in ssh-keygen -t ed25519 -C "$machine" -f "$key"
  fi
fi

# ssh config entries for the git hosts (only added when missing; chezmoi doesn't manage ~/.ssh/config yet)
add_host() { # add_host <Host> <HostName>
  touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
  grep -q "^Host $1\$" "$HOME/.ssh/config" && return
  {
    printf '\nHost %s\n  HostName %s\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$1" "$2" "$key"
    printf '  AddKeysToAgent yes\n  StrictHostKeyChecking accept-new\n'
    if [ "$os" = Darwin ]; then printf '  UseKeychain yes\n'; fi
  } >> "$HOME/.ssh/config"
}
add_host "$GITLAB" "$GITLAB"
if [ "$work" = true ]; then
  add_host github-dotfiles github.com
  repo="${DOTFILES_REPO:-$WORK_REPO}"
else
  repo="${DOTFILES_REPO:-$PERSONAL_REPO}"
fi

say "Add this machine's public key"
cat "$key.pub"
{ command -v pbcopy >/dev/null 2>&1 && pbcopy < "$key.pub" && note "(copied to the clipboard)"; } || true
if [ "$work" = true ]; then
  note "Work machine: deploy keys only, so it can't reach your other repos."
  note "1. GitHub mirror, read-only (title: $machine):"
  note "   https://github.com/Brikkel/dotfiles/settings/keys/new"
  note "2. work-notes on GitLab, tick 'Grant write permissions' (over WireGuard if not at home):"
  note "   https://$GITLAB/brikkel/work-notes/-/settings/repository#js-deploy-keys-settings"
else
  note "Personal machine: add it to your GitLab account (title: $machine):"
  note "   https://$GITLAB/-/user_settings/ssh_keys"
fi

until git ls-remote "$repo" >/dev/null 2>&1; do
  [ -n "$NONINTERACTIVE" ] && { echo "install.sh: can't reach $repo" >&2; exit 1; }
  ask "Press Enter once the key is added (or Ctrl-C to stop)..." ""
  git ls-remote "$repo" >/dev/null 2>&1 || note "Still can't reach $repo; check the key (and the home network for GitLab)."
done

# --- 4. chezmoi -----------------------------------------------------------------------------------
say "Applying the dotfiles (chezmoi asks the remaining questions)"
reprompt=""
if [ -f "$HOME/.config/chezmoi/chezmoi.toml" ]; then
  ask "chezmoi already has answers from an earlier run. Answer its questions again? (y/n)" n
  case "$REPLY" in y*|Y*) reprompt=--prompt ;; esac
fi
note "chezmoi's questions take ONE key, without Enter: y / n, or the first letter of a choice."
note "Enter alone takes the default. Don't type whole words: the extra letters answer the next questions."
# These prompt texts must match .chezmoi.toml.tmpl exactly.
set -- --apply $reprompt \
  --promptString "machine name (short: wireguard peer + host lists)=$machine" \
  --promptBool "work machine? (y/n)=$work"
if [ -n "$NONINTERACTIVE" ]; then
  chezmoi init "$@" --promptDefaults "$repo" </dev/null
else
  chezmoi init "$@" "$repo" </dev/tty
fi

say "Done. Open a new terminal (kitty on a desktop) to start using it."
if [ "$os" = Darwin ]; then note "Sign in to the App Store if the App Store apps were skipped, then run: chezmoi apply"; fi
exit 0
