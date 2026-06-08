#!/usr/bin/env bash
# install.sh — bootstrap (lần đầu) + startup (mỗi lần restart)
# Tất cả tools cài vào /home/data/ để persist qua pod restart.
# Lần sau chỉ cần: bash /home/data/install.sh

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SOURCED=false
    set -euo pipefail
else
    _SOURCED=true
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

DATA=/home/data
mkdir -p "$DATA"

# ── Persistent paths ──────────────────────────────────────────────────────
export PATH="$DATA/.local/bin:$DATA/.npm-global/bin:$PATH"
export NVM_DIR="$DATA/.nvm"
export NPM_CONFIG_PREFIX="$DATA/.npm-global"
export UV_INSTALL_DIR="$DATA/.local/bin"
export UV_TOOL_DIR="$DATA/.uv/tools"
export UV_TOOL_BIN_DIR="$DATA/.local/bin"

# =============================================================================
# INSTALL SECTION — idempotent, skip nếu đã có trong /home/data/
# =============================================================================

install_ssh() {
    if command -v sshd &>/dev/null; then
        success "openssh-server already installed"
        return
    fi
    info "Installing openssh-server..."
    apt-get install -y openssh-server -q 2>/dev/null
    success "openssh-server installed"
}

install_uv() {
    if [[ -x "$DATA/.local/bin/uv" ]]; then
        success "uv already installed: $($DATA/.local/bin/uv --version)"
        return
    fi
    info "Installing uv → $DATA/.local/bin ..."
    curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$DATA/.local/bin" sh
    success "uv installed: $(uv --version)"
}

install_huggingface() {
    if [[ -x "$DATA/.local/bin/hf" ]]; then
        success "hf already installed"
        return
    fi
    info "Installing huggingface-cli & hf via uv tool..."
    uv tool install "huggingface_hub[cli]"
    curl -LsSf https://hf.co/cli/install.sh | bash -s || true
    local hf_venv="$HOME/.hf-cli/venv"
    local hf_bin="$DATA/.local/bin/hf"
    if [[ -f "$hf_venv/bin/python3" ]] && ! "$hf_bin" sync --help &>/dev/null 2>&1; then
        info "Patching hf binary to fix sys.path leak..."
        cat > "$hf_bin" << HFEOF
#!${hf_venv}/bin/python3
import sys
sys.path = [p for p in sys.path if '/opt/venv' not in p]
from huggingface_hub.cli.hf import main
main()
HFEOF
        chmod +x "$hf_bin"
    fi
    success "hf installed"
}

install_hf_xet() {
    local targets=()
    for python in /opt/venv/bin/python3 "$HOME/.hf-cli/venv/bin/python3"; do
        [[ -x "$python" ]] || continue
        "$python" -c "import huggingface_hub" 2>/dev/null || continue
        "$python" -c "import hf_xet" 2>/dev/null || targets+=("$python")
    done
    [[ ${#targets[@]} -eq 0 ]] && { success "hf_xet already installed"; return; }
    for python in "${targets[@]}"; do
        "$python" -m pip install -q hf_xet
    done
    success "hf_xet installed"
}

install_nvitop() {
    if [[ -x "$DATA/.local/bin/nvitop" ]]; then
        success "nvitop already installed"
        return
    fi
    info "Installing nvitop → $DATA/.local/bin ..."
    uv tool install nvitop
    success "nvitop installed"
}

install_pm2() {
    if [[ -x "$DATA/.npm-global/bin/pm2" ]]; then
        success "pm2 already installed: $($DATA/.npm-global/bin/pm2 --version)"
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
        return
    fi
    info "Installing NVM → $NVM_DIR ..."
    if [[ ! -f "$NVM_DIR/nvm.sh" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | \
            NVM_DIR="$NVM_DIR" bash
    fi
    set +u
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    node --version > "$DATA/.node_version"
    set -u
    info "Installing pm2 → $DATA/.npm-global/bin ..."
    npm install -g pm2
    success "pm2 installed: $(pm2 --version)"
}

setup_github_ssh() {
    local data_ssh="$DATA/.ssh"
    mkdir -p "$data_ssh" && chmod 700 "$data_ssh"
    if [[ ! -L /root/.ssh ]]; then
        cp -r /root/.ssh/. "$data_ssh/" 2>/dev/null || true
        rm -rf /root/.ssh
        ln -sf "$data_ssh" /root/.ssh
        success "~/.ssh symlinked → $data_ssh"
    fi
    local key="$data_ssh/id_ed25519"
    if [[ ! -f "$key" ]]; then
        info "Generating SSH key (ed25519)..."
        ssh-keygen -t ed25519 -C "github-$(hostname)" -f "$key" -N ""
        success "SSH key created: $key"
    else
        success "SSH key exists: $key"
    fi
    [[ -f "$data_ssh/authorized_keys" ]] && \
        cp "$data_ssh/authorized_keys" "$DATA/.ssh_authorized_keys" 2>/dev/null || true
    eval "$(ssh-agent -s)" &>/dev/null
    ssh-add "$key" 2>/dev/null || true
    echo ""
    echo "  ┌─ Public key (add to GitHub > Settings > SSH keys) ───────────────"
    echo "  │"
    sed 's/^/  │  /' "$key.pub"
    echo "  │"
    echo "  └───────────────────────────────────────────────────────────────────"
    echo "  https://github.com/settings/ssh/new"
    echo ""
}

configure_shell() {
    local rc_file="$HOME/.bashrc"
    local marker="# >>> dotfile-A100 managed >>>"
    if grep -qF "$marker" "$rc_file" 2>/dev/null; then
        success "Shell config already patched"
        return
    fi
    info "Patching $rc_file..."
    cat >> "$rc_file" << 'SHELLBLOCK'

# >>> dotfile-A100 managed >>>
export DATA=/home/data
export PATH="$DATA/.local/bin:$DATA/.npm-global/bin:$PATH"
export NVM_DIR="$DATA/.nvm"
export UV_TOOL_DIR="$DATA/.uv/tools"
export UV_TOOL_BIN_DIR="$DATA/.local/bin"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
if command -v uv &>/dev/null; then
    eval "$(uv generate-shell-completion bash 2>/dev/null)" || true
fi
# <<< dotfile-A100 managed <<<
SHELLBLOCK
    set +u; source "$rc_file" 2>/dev/null || true; set -u
    success "Shell config updated"
}

# =============================================================================
# STARTUP SECTION — chạy mỗi lần restart (~5 giây)
# =============================================================================

startup_ssh() {
    mkdir -p /run/sshd
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    # Restore authorized_keys
    if [[ -f "$DATA/.ssh_authorized_keys" ]]; then
        cp "$DATA/.ssh_authorized_keys" /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
    fi
    # Restore SSH keys nếu /root/.ssh chưa phải symlink
    if [[ ! -L /root/.ssh ]] && [[ -d "$DATA/.ssh" ]]; then
        cp "$DATA/.ssh/id_ed25519"     /root/.ssh/id_ed25519     2>/dev/null || true
        cp "$DATA/.ssh/id_ed25519.pub" /root/.ssh/id_ed25519.pub 2>/dev/null || true
        chmod 600 /root/.ssh/id_ed25519 2>/dev/null || true
    fi
    /usr/sbin/sshd 2>/dev/null
    success "sshd started"
}

startup_tools() {
    # Activate NVM + node
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" --no-use 2>/dev/null || true
    if [[ -f "$DATA/.node_version" ]]; then
        nvm use "$(cat "$DATA/.node_version")" 2>/dev/null || nvm use --lts 2>/dev/null || true
    else
        nvm use --lts 2>/dev/null || true
    fi
    success "Tools: uv=$(uv --version 2>/dev/null | awk '{print $2}') | node=$(node --version 2>/dev/null) | pm2=$(pm2 --version 2>/dev/null)"
}

startup_pm2() {
    mkdir -p "$DATA/.pm2"
    if [[ ! -L /root/.pm2 ]]; then
        rm -rf /root/.pm2
        ln -sf "$DATA/.pm2" /root/.pm2
    fi
    pm2 resurrect 2>/dev/null && success "PM2 jobs resurrected" || warn "PM2: no saved state"
}

startup_tailscale() {
    if ! command -v tailscale &>/dev/null; then
        info "Installing tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh -s -- -q
    fi
    pkill tailscaled 2>/dev/null || true; sleep 1
    tailscaled --tun=userspace-networking --state="$DATA/tailscale-state.json" \
        > "$DATA/tailscaled.log" 2>&1 &
    sleep 3
    if [[ -f "$DATA/.tailscale_authkey" ]]; then
        tailscale up --authkey="$(cat "$DATA/.tailscale_authkey")" \
            --accept-routes --hostname="$(hostname)" 2>/dev/null \
            && success "Tailscale: $(tailscale ip -4)" \
            || warn "Tailscale: auth failed — run 'tailscale up' manually"
    else
        warn "No auth key at $DATA/.tailscale_authkey — run 'tailscale up' manually"
    fi
}

startup_bore() {
    command -v bore &>/dev/null || return
    pkill bore 2>/dev/null || true; sleep 1
    nohup bash -c "while true; do bore local 22 --to bore.pub 2>&1 | tee $DATA/bore.log; sleep 3; done" &
    sleep 3
    echo "Bore: $(grep -o 'bore.pub:[0-9]*' "$DATA/bore.log" 2>/dev/null | tail -1 || echo 'not connected')"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  dotfile-A100  —  $(date)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Install (idempotent — skip nếu đã có)
    install_ssh
    install_uv
    install_huggingface
    install_hf_xet
    install_nvitop
    install_pm2
    configure_shell
    setup_github_ssh

    # Startup (luôn chạy)
    startup_ssh
    startup_tools
    startup_pm2
    startup_tailscale
    startup_bore

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "Done!  $(date)"
    echo ""
    echo "  Lần sau restart: bash /home/data/install.sh"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$_SOURCED" == false ]]; then
        echo -e "\n${YELLOW}  ⚠ Activate ngay:${NC}  source ~/.bashrc\n"
    fi
}

main "$@"
