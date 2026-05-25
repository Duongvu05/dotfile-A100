#!/usr/bin/env bash

# Detect nếu đang được source hay execute
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _SOURCED=false
    set -euo pipefail
else
    _SOURCED=true
fi

# ─── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# ─── uv ───────────────────────────────────────────────────────────────────────
install_uv() {
    if command -v uv &>/dev/null; then
        success "uv already installed: $(uv --version)"
        return
    fi

    info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Source the env so uv is available in this session
    if [[ -f "$HOME/.local/bin/env" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.local/bin/env"
    fi
    export PATH="$HOME/.local/bin:$PATH"

    success "uv installed: $(uv --version)"
}

# ─── Hugging Face CLI (huggingface-cli) ───────────────────────────────────────
install_huggingface() {
    if command -v huggingface-cli &>/dev/null; then
        success "huggingface-cli already installed: $(huggingface-cli version)"
        return
    fi

    info "Installing huggingface-cli via uv tool..."
    uv tool install "huggingface_hub[cli]"

    success "huggingface-cli installed: $(huggingface-cli version)"
}

# ─── hf CLI (with bucket/sync support) ────────────────────────────────────────
install_hf() {
    # Verify hf is the official binary (supports sync), not the broken Python wrapper
    if command -v hf &>/dev/null && hf sync --help &>/dev/null 2>&1; then
        success "hf already installed: $(hf version 2>/dev/null | head -1)"
        return
    fi

    info "Installing hf CLI..."
    curl -LsSf https://hf.co/cli/install.sh | bash -s || true

    export PATH="$HOME/.local/bin:$PATH"

    # The hf-cli venv may leak sys.path to /opt/venv which has a different huggingface_hub.
    # Patch the hf binary to exclude /opt/venv from sys.path so it uses its own packages.
    local hf_venv="$HOME/.hf-cli/venv"
    local hf_bin="$HOME/.local/bin/hf"
    if [[ -f "$hf_venv/bin/python3" ]] && ! hf sync --help &>/dev/null 2>&1; then
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

    success "hf installed: $(hf version 2>/dev/null | head -1)"
}

# ─── nvitop ───────────────────────────────────────────────────────────────────
install_nvitop() {
    if command -v nvitop &>/dev/null; then
        success "nvitop already installed"
        return
    fi

    info "Installing nvitop via uv tool..."
    uv tool install nvitop

    success "nvitop installed"
}

# ─── PM2 ──────────────────────────────────────────────────────────────────────
install_pm2() {
    if command -v pm2 &>/dev/null; then
        success "pm2 already installed: $(pm2 --version)"
        return
    fi

    # If npm is already available, use it directly
    if command -v npm &>/dev/null; then
        info "Installing pm2 via npm..."
        npm install -g pm2
        success "pm2 installed: $(pm2 --version)"
        return
    fi

    # No npm — install Node.js via NVM first
    info "Node.js not found. Installing NVM + Node.js LTS..."
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

    if [[ ! -f "$nvm_dir/nvm.sh" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi

    # nvm scripts use unbound variables internally — disable -u for the whole block
    set +u
    # shellcheck source=/dev/null
    source "$nvm_dir/nvm.sh"
    nvm install --lts
    nvm use --lts
    set -u

    # Add the active node's bin to PATH so npm/pm2 are visible immediately
    local node_bin
    node_bin="$(set +u; source "$nvm_dir/nvm.sh" 2>/dev/null; nvm which current 2>/dev/null | xargs dirname)" || true
    [[ -n "$node_bin" ]] && export PATH="$node_bin:$PATH"

    info "Installing pm2 via npm..."
    npm install -g pm2

    # Ensure npm global bin is also in PATH
    local npm_global_bin
    npm_global_bin="$(npm root -g 2>/dev/null | sed 's|/node_modules$|/bin|')" || true
    [[ -n "$npm_global_bin" ]] && export PATH="$npm_global_bin:$PATH"

    # Persist NVM init in shell config if not already there
    local rc_file=""
    case "${SHELL:-}" in
        */zsh)  rc_file="$HOME/.zshrc" ;;
        */bash) rc_file="$HOME/.bashrc" ;;
    esac

    local nvm_marker="# >>> nvm managed >>>"
    if [[ -n "$rc_file" ]] && ! grep -qF "$nvm_marker" "$rc_file" 2>/dev/null; then
        cat >> "$rc_file" <<NVMBLOCK

$nvm_marker
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"
# <<< nvm managed <<<
NVMBLOCK
    fi

    success "pm2 installed: $(pm2 --version)"
}

# ─── Shell config ─────────────────────────────────────────────────────────────
configure_shell() {
    local rc_file=""
    case "${SHELL:-$(basename "$SHELL")}" in
        */zsh)  rc_file="$HOME/.zshrc" ;;
        */bash) rc_file="$HOME/.bashrc" ;;
        *)      warn "Unknown shell — skipping shell config"; return ;;
    esac

    local marker="# >>> dotfile-A100 managed >>>"
    if grep -qF "$marker" "$rc_file" 2>/dev/null; then
        success "Shell config already patched in $rc_file"
        return
    fi

    info "Patching $rc_file..."
    cat >> "$rc_file" <<'SHELLBLOCK'

# >>> dotfile-A100 managed >>>
export PATH="$HOME/.local/bin:$PATH"

# uv shell completions
if command -v uv &>/dev/null; then
    eval "$(uv generate-shell-completion "${SHELL##*/}" 2>/dev/null)" || true
fi
# <<< dotfile-A100 managed <<<
SHELLBLOCK

    # Source ngay trong session hiện tại (tắt -u tạm vì .bashrc dùng $PS1)
    set +u
    # shellcheck source=/dev/null
    source "$rc_file" 2>/dev/null || true
    set -u
    success "Shell config updated và đã source $rc_file"
}

# ─── GitHub SSH key ────────────────────────────────────────────────────────────
setup_github_ssh() {
    local key="$HOME/.ssh/id_ed25519"

    if [[ -f "$key" ]]; then
        success "SSH key đã tồn tại: $key"
    else
        info "Generating SSH key (ed25519)..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "github-$(hostname)" -f "$key" -N ""
        success "SSH key đã tạo: $key"
    fi

    # Thêm vào ssh-agent
    eval "$(ssh-agent -s)" &>/dev/null
    ssh-add "$key" 2>/dev/null || true

    echo ""
    echo "  ┌─ Public key (thêm vào GitHub > Settings > SSH keys) ─────────────"
    echo "  │"
    sed 's/^/  │  /' "$key.pub"
    echo "  │"
    echo "  └───────────────────────────────────────────────────────────────────"
    echo "  https://github.com/settings/ssh/new"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  dotfile-A100 bootstrap"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    install_uv
    install_huggingface
    install_hf
    install_nvitop
    install_pm2
    configure_shell
    setup_github_ssh

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "Bootstrap complete!"
    echo ""
    echo "  Next steps:"
    echo "    hf auth login           # đăng nhập HF account"
    echo "    ssh -T git@github.com   # kiểm tra GitHub SSH"
    echo "    pm2 ls                  # xem trạng thái jobs"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$_SOURCED" == false ]]; then
        echo ""
        echo -e "${YELLOW}  ⚠ Chạy lệnh sau để dùng ngay không cần mở terminal mới:${NC}"
        echo "    source ~/.bashrc"
        echo ""
    fi
}

main "$@"
