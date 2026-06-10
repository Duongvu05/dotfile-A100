#!/usr/bin/env bash
# setup.sh — dotfile-A100
#
# Usage:
#   bash setup.sh           → startup mode  (mỗi khi pod restart, ~10s)
#   bash setup.sh install   → install mode  (lần đầu tiên, ~3 phút)

MODE="${1:-startup}"

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }

DATA=/home/data
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$DATA/.local/bin:$DATA/.npm-global/bin:$PATH"
export NVM_DIR="$DATA/.nvm"
export UV_TOOL_DIR="$DATA/.uv/tools"
export UV_TOOL_BIN_DIR="$DATA/.local/bin"
export UV_INSTALL_DIR="$DATA/.local/bin"
export NPM_CONFIG_PREFIX="$DATA/.npm-global"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$MODE" == "install" ]]; then
    info "dotfile-A100 INSTALL — $(date)"
else
    info "Pod startup — $(date)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ══════════════════════════════════════════════════════════════════════════
# INSTALL-ONLY FUNCTIONS  (chạy 1 lần duy nhất)
# ══════════════════════════════════════════════════════════════════════════

install_uv() {
    if [[ -x "$DATA/.local/bin/uv" ]]; then
        ok "uv already installed: $($DATA/.local/bin/uv --version)"; return
    fi
    info "Installing uv → $DATA/.local/bin ..."
    curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$DATA/.local/bin" sh
    ok "uv installed: $(uv --version)"
}

install_huggingface() {
    if [[ -x "$DATA/.local/bin/hf" ]]; then ok "hf already installed"; return; fi
    info "Installing huggingface-cli & hf ..."
    uv tool install "huggingface_hub[cli]"
    curl -LsSf https://hf.co/cli/install.sh | bash -s || true
    local hf_venv="$HOME/.hf-cli/venv"
    local hf_bin="$DATA/.local/bin/hf"
    if [[ -f "$hf_venv/bin/python3" ]] && ! "$hf_bin" sync --help &>/dev/null 2>&1; then
        cat > "$hf_bin" << HFEOF
#!${hf_venv}/bin/python3
import sys
sys.path = [p for p in sys.path if '/opt/venv' not in p]
from huggingface_hub.cli.hf import main
main()
HFEOF
        chmod +x "$hf_bin"
    fi
    ok "hf installed"
}

install_hf_xet() {
    for python in /opt/venv/bin/python3 "$HOME/.hf-cli/venv/bin/python3"; do
        [[ -x "$python" ]] || continue
        "$python" -c "import huggingface_hub" 2>/dev/null || continue
        "$python" -c "import hf_xet" 2>/dev/null && continue
        info "Installing hf_xet into $(dirname "$python")..."
        "$python" -m pip install -q hf_xet
    done
    ok "hf_xet installed"
}

install_nvitop() {
    if [[ -x "$DATA/.local/bin/nvitop" ]]; then ok "nvitop already installed"; return; fi
    info "Installing nvitop ..."
    uv tool install nvitop
    ok "nvitop installed"
}

install_pm2() {
    if [[ -x "$DATA/.npm-global/bin/pm2" ]]; then
        ok "pm2 already installed: $($DATA/.npm-global/bin/pm2 --version)"
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
        return
    fi
    info "Installing NVM → $NVM_DIR ..."
    if [[ ! -f "$NVM_DIR/nvm.sh" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | \
            NVM_DIR="$NVM_DIR" bash
    fi
    set +u; source "$NVM_DIR/nvm.sh"; nvm install --lts; nvm use --lts; set -u
    node --version > "$DATA/.node_version"
    npm install -g pm2
    ok "pm2 installed: $(pm2 --version)"
}


setup_pm2_persist() {
    mkdir -p "$DATA/.pm2"
    if [[ ! -L /root/.pm2 ]]; then
        cp -r /root/.pm2/. "$DATA/.pm2/" 2>/dev/null || true
        rm -rf /root/.pm2
        ln -sf "$DATA/.pm2" /root/.pm2
        ok "PM2 data symlinked → $DATA/.pm2"
    fi
    pm2 save 2>/dev/null || true
    ok "PM2 state saved"
}

setup_github_ssh() {
    local data_ssh="$DATA/.ssh"
    local key="$data_ssh/id_ed25519_github"
    mkdir -p "$data_ssh" && chmod 700 "$data_ssh"
    if [[ ! -f "$key" ]]; then
        info "Generating GitHub SSH key (ed25519)..."
        ssh-keygen -t ed25519 -C "github-a100-pod" -f "$key" -N "" -q
        ok "SSH key created: $key"
    else
        ok "SSH key exists: $key"
    fi
    # Write SSH config so git always uses this key for GitHub
    cat > "$data_ssh/config" << 'EOF'
Host github.com
    IdentityFile ~/.ssh/id_ed25519_github
    StrictHostKeyChecking no
EOF
    chmod 600 "$data_ssh/config"
    [[ -f "$data_ssh/authorized_keys" ]] && \
        cp "$data_ssh/authorized_keys" "$DATA/.ssh_authorized_keys" || true
    echo ""
    echo "  ┌─ Public key (add to GitHub > Settings > SSH keys) ─────────"
    sed 's/^/  │  /' "$key.pub"
    echo "  └─────────────────────────────────────────────────────────────"
    echo "  https://github.com/settings/ssh/new"
    echo ""
}

configure_shell() {
    local rc_file="$HOME/.bashrc"
    local marker="# >>> dotfile-A100 managed >>>"
    if grep -qF "$marker" "$rc_file" 2>/dev/null; then ok "Shell config already patched"; return; fi
    info "Patching $rc_file..."
    cat >> "$rc_file" << SHELLBLOCK

$marker
export DATA=/home/data
export PATH="\$DATA/.local/bin:\$DATA/.npm-global/bin:\$PATH"
export NVM_DIR="\$DATA/.nvm"
export UV_TOOL_DIR="\$DATA/.uv/tools"
export UV_TOOL_BIN_DIR="\$DATA/.local/bin"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
# <<< dotfile-A100 managed <<<
SHELLBLOCK
    ok "Shell config updated"
}

# ══════════════════════════════════════════════════════════════════════════
# STARTUP FUNCTIONS  (chạy mỗi lần restart)
# ══════════════════════════════════════════════════════════════════════════

start_sshd() {
    # apt-get update chỉ chạy nếu sshd chưa có (pod mới, chưa install)
    if ! command -v sshd &>/dev/null; then
        info "sshd not found — installing (apt-get update + openssh-server)..."
        apt-get update -q 2>/dev/null
        apt-get install -y openssh-server libgl1 libglib2.0-0 -q 2>/dev/null
    fi
    mkdir -p /run/sshd

    # Restore authorized_keys từ persistent storage
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    if [[ -f "$DATA/.ssh_authorized_keys" ]]; then
        cp "$DATA/.ssh_authorized_keys" /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
    fi

    # Restore GitHub SSH key and config from persistent storage
    if [[ -d "$DATA/.ssh" ]]; then
        local key="$DATA/.ssh/id_ed25519_github"
        if [[ -f "$key" ]]; then
            cp "$key"      /root/.ssh/id_ed25519_github     2>/dev/null || true
            cp "$key.pub"  /root/.ssh/id_ed25519_github.pub 2>/dev/null || true
            chmod 600 /root/.ssh/id_ed25519_github 2>/dev/null || true
        fi
        if [[ -f "$DATA/.ssh/config" ]]; then
            cp "$DATA/.ssh/config" /root/.ssh/config
            chmod 600 /root/.ssh/config
        fi
    fi

    /usr/sbin/sshd 2>/dev/null && ok "sshd started" || warn "sshd failed to start"
}

activate_tools() {
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
    if [[ -f "$DATA/.node_version" ]]; then
        nvm use "$(cat "$DATA/.node_version")" 2>/dev/null || nvm use --lts 2>/dev/null || true
    else
        nvm use --lts 2>/dev/null || true
    fi
    ok "Tools: uv=$(uv --version 2>/dev/null | awk '{print $2}'), node=$(node --version 2>/dev/null), pm2=$(pm2 --version 2>/dev/null)"
}

start_pm2() {
    mkdir -p "$DATA/.pm2"
    if [[ ! -L /root/.pm2 ]]; then
        rm -rf /root/.pm2
        ln -sf "$DATA/.pm2" /root/.pm2
    fi
    pm2 resurrect 2>/dev/null && ok "PM2 jobs resurrected" || warn "PM2: no saved state"
}

start_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        info "Installing tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh -s -- -q
    fi
    pkill tailscaled 2>/dev/null || true; sleep 1
    tailscaled --tun=userspace-networking --state="$DATA/tailscale-state.json" \
        > "$DATA/tailscaled.log" 2>&1 &
    sleep 3
    if [[ ! -f "$DATA/.tailscale_authkey" ]]; then
        warn "No Tailscale auth key at $DATA/.tailscale_authkey"
        return 1
    fi
    if tailscale up --authkey="$(cat "$DATA/.tailscale_authkey")" \
            --accept-routes --hostname="$(hostname)" 2>/dev/null; then
        ok "Tailscale: $(tailscale ip -4)"
        return 0
    else
        warn "Tailscale auth failed — run 'tailscale up' manually"
        return 1
    fi
}


# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════

if [[ "$MODE" == "install" ]]; then
    # ── First-time install ───────────────────────────────────────────────
    apt-get update -q 2>/dev/null
    install_uv
    install_huggingface
    install_hf_xet
    install_nvitop
    install_pm2
    setup_pm2_persist
    configure_shell
    setup_github_ssh

    # Deploy this script itself to /home/data/ for startup use
    cp "$SCRIPT_DIR/setup.sh" "$DATA/setup.sh" && chmod +x "$DATA/setup.sh"
    ok "setup.sh deployed → $DATA/setup.sh"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "INSTALL DONE — $(date)"
    echo ""
    echo "  Next steps:"
    echo "    echo 'tskey-auth-...' > $DATA/.tailscale_authkey"
    echo "    bash $DATA/setup.sh          ← chạy startup ngay"
    echo "    hf auth login"
    echo "    ssh -T git@github.com"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}  ⚠ Activate ngay:${NC}  source ~/.bashrc"

else
    # ── Every-restart startup ────────────────────────────────────────────
    start_sshd
    activate_tools
    start_pm2

    start_tailscale

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "STARTUP DONE — $(date)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
