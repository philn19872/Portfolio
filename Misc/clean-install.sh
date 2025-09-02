#!/bin/bash

# Title: Kali Linux Post-Install Setup
# Author: Phil
# Description: Modular script to automate Kali setup tasks with optional dry-run mode

show_help() {
  echo "🛠️ Kali Linux Post-Install Setup Script"
  echo ""
  echo "Usage: sudo ./clean-install.sh [options]"
  echo ""
  echo "Options:"
  echo "  --run        Execute the setup and apply changes"
  echo "  --dry-run    Simulate actions without applying changes"
  echo "  -h, --help   Show this help message and exit"
  echo ""
  echo "You must specify either --run or --dry-run to proceed."
  echo ""
  echo "Example:"
  echo "  sudo ./clean-install.sh --dry-run"
}

# ─────────────────────────────────────────────────────────────
# Parse command-line arguments
RUN_MODE=false
DRY_RUN=false
SHOW_HELP=false

# Show help if no arguments are provided
if [ "$#" -eq 0 ]; then
  SHOW_HELP=true
fi

for arg in "$@"; do
  case "$arg" in
    --run)
      RUN_MODE=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      SHOW_HELP=true
      ;;
    *)
      echo "❌ Unknown option: $arg"
      SHOW_HELP=true
      ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  show_help
  exit 0
fi

# Enforce that either --run or --dry-run must be passed
if [ "$RUN_MODE" = false ] && [ "$DRY_RUN" = false ]; then
  echo "⚠️ You must specify either --run or --dry-run."
  show_help
  exit 1
fi

# Set DRY_RUN flag based on RUN_MODE
if [ "$RUN_MODE" = true ]; then
  DRY_RUN=false
else
  DRY_RUN=true
  echo "🚧 DRY RUN MODE ENABLED — No changes will be applied."
fi

# ─────────────────────────────────────────────────────────────
# Utility: run_cmd executes or simulates commands
run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "🔸 [DRY RUN] $*"
  else
    eval "$@"
  fi
}

# ─────────────────────────────────────────────────────────────
# Determine actual user and home directory
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$TARGET_USER")

# Warn if running as root directly
if [ "$EUID" -eq 0 ] && [ -z "$SUDO_USER" ]; then
  echo "⚠️ Warning: You're running this script as root. Use: sudo ./clean-install.sh"
fi

# ─────────────────────────────────────────────────────────────
update_system() {
  echo "🔧 Updating system..."
  run_cmd "sudo apt update"
  run_cmd "sudo apt full-upgrade -y"
  run_cmd "sudo apt dist-upgrade -y"
  run_cmd "sudo apt autoremove -y"
  run_cmd "sudo apt autoclean -y"
}

# ─────────────────────────────────────────────────────────────
fix_audio_vmware() {
  echo "🔊 Applying audio fix for VMware..."

  if ! command -v wireplumber &> /dev/null; then
    echo "⚠️ WirePlumber not found. Installing..."
    run_cmd "sudo apt install -y wireplumber"
  fi

  run_cmd "mkdir -p \"$USER_HOME/.config/wireplumber/wireplumber.conf.d\""
  CONFIG_FILE="$USER_HOME/.config/wireplumber/wireplumber.conf.d/50-alsa-config.conf"

  if [ "$DRY_RUN" = true ]; then
    echo "🔸 [DRY RUN] Writing ALSA config to $CONFIG_FILE"
  else
    cat <<EOF > "$CONFIG_FILE"
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_output.*" }
    ]
    actions = {
      update-props = {
        api.alsa.period-size   = 1024
        api.alsa.headroom      = 8192
      }
    }
  }
]
EOF
  fi

  echo "🔁 Attempting to restart WirePlumber..."
  if systemctl --user status wireplumber &> /dev/null; then
    run_cmd "systemctl --user restart wireplumber pipewire pipewire-pulse"
  else
    echo "⚠️ Could not restart user services. Reboot or run manually:"
    echo "    systemctl --user restart wireplumber pipewire pipewire-pulse"
  fi
}

# ─────────────────────────────────────────────────────────────
install_packages() {
  echo "📦 Installing essential packages..."
  PACKAGES=(
    firmware-linux
    firmware-realtek
    firmware-atheros
    kali-linux-everything
    poppler-utils
    gedit
    rlwrap
    libguestfs-tools
    tmux
    python3-pip
    python3-virtualenv
    pipx
  )
  for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" &> /dev/null; then
      echo "✅ $pkg already installed."
    else
      run_cmd "sudo apt install -y $pkg"
    fi
  done
}

# ─────────────────────────────────────────────────────────────
setup_go_environment() {
  echo "🐹 Checking Go environment setup..."

  GOPATH="$USER_HOME/go"
  PROFILE="$USER_HOME/.bashrc"  # Adjust if using Zsh

  if grep -q "export GOPATH=" "$PROFILE" && grep -q "\$GOPATH/bin" "$PROFILE"; then
    echo "✅ Go environment already configured in $PROFILE — skipping setup."
  else
    echo "🔧 Setting up Go environment variables..."
    run_cmd "echo 'export GOPATH=$GOPATH' >> \"$PROFILE\""
    run_cmd "echo 'export PATH=\$PATH:\$GOPATH/bin' >> \"$PROFILE\""
    echo "✅ GOPATH and PATH added to $PROFILE"
  fi

  export GOPATH="$GOPATH"
  export PATH="$PATH:$GOPATH/bin"
}

# ─────────────────────────────────────────────────────────────
install_kerbrute() {
  echo "🐹 Installing Kerbrute..."

  run_cmd "go install github.com/ropnop/kerbrute@latest"

  # Check if kerbrute is accessible
  if command -v kerbrute &> /dev/null; then
    echo "✅ kerbrute is accessible from PATH."
  elif [ -f "$GOPATH/bin/kerbrute" ]; then
    echo "⚠️ kerbrute binary found but not in PATH. Creating symlink..."
    run_cmd "sudo ln -sf \"$GOPATH/bin/kerbrute\" /usr/local/bin/kerbrute"
    echo "✅ kerbrute symlinked to /usr/local/bin"
  else
    echo "❌ kerbrute installation failed or binary not found."
  fi
}

# ─────────────────────────────────────────────────────────────
install_sublime_text() {
  echo "📝 Installing Sublime Text..."
  run_cmd "wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo tee /etc/apt/keyrings/sublimehq-pub.asc > /dev/null"
  run_cmd "echo -e 'Types: deb\nURIs: https://download.sublimetext.com/\nSuites: apt/stable/\nSigned-By: /etc/apt/keyrings/sublimehq-pub.asc' | sudo tee /etc/apt/sources.list.d/sublime-text.sources > /dev/null"
  run_cmd "sudo apt update"
  run_cmd "sudo apt install -y sublime-text"
  command -v subl &> /dev/null && echo "✅ Sublime Text installed." || echo "❌ Sublime install failed."
}

# ─────────────────────────────────────────────────────────────
setup_tmux() {
  echo "🧱 Setting up tmux..."

  TPM_DIR="$USER_HOME/.tmux/plugins/tpm"

  if [ -d "$TPM_DIR" ] && [ "$(ls -A "$TPM_DIR")" ]; then
    echo "ℹ️ TPM already exists at $TPM_DIR — skipping clone."
  else
    run_cmd "git clone https://github.com/tmux-plugins/tpm \"$TPM_DIR\""
  fi

  TMUX_CONF="$USER_HOME/.tmux.conf"
  if [ "$DRY_RUN" = true ]; then
    echo "🔸 [DRY RUN] Writing tmux config to $TMUX_CONF"
  else
    cat <<'EOF' > "$TMUX_CONF"
# Remap prefix
set -g prefix C-a
bind C-a send-prefix
unbind C-b

# Use Alt-arrow keys to switch panes
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# Use Shift-arrow to switch windows
bind -n S-Left previous-window
bind -n S-Right next-window

# QOL stuff
set -g allow-rename off

# Search mode VT (default is emac)
set-window-option -g mode-keys vi
set -g mode-keys vi

# Mouse
set -g mouse on
set -g @yank_selection_mouse 'clipboard'

# Window and pane numbering
set -g base-index 1
set -g pane-base-index 1
set -g renumber-windows on

# Easier window split keys
bind-key h split-window -v 
bind h split-window -c "#{pane_current_path}"
bind-key v split-window -h 
bind v split-window -h -c "#{pane_current_path}"

# Move window left or right
bind-key -n C-S-Left swap-window -t -1
bind-key -n C-S-Right swap-window -t +1

# Create new window stays in current directory
bind c new-window -c "#{pane_current_path}"

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'noscript/tmux-mighty-scroll'
set -g @plugin 'tmux-plugins/tmux-yank'

# Initialise TMUX plugin manager (keep this line at bottom of .tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
EOF
  fi

  echo "✅ tmux configured. Launch tmux and press prefix + I to install plugins."
}

# ─────────────────────────────────────────────────────────────
setup_python_tools() {
  echo "🐍 Finalizing Python tooling..."
  run_cmd "sudo -u "$SUDO_USER" pipx ensurepath"
  echo "✅ Python tooling setup complete."
}

# ─────────────────────────────────────────────────────────────
# Execute all setup steps
update_system
fix_audio_vmware
install_packages
setup_go_environment
install_kerbrute
install_sublime_text
setup_tmux
setup_python_tools

echo "🎉 Setup complete. Reboot recommended to apply all changes."
