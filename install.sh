#!/usr/bin/env bash
set -euo pipefail

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
    if command -v hf &>/dev/null; then
        success "hf already installed: $(hf version 2>/dev/null | head -1)"
        return
    fi

    info "Installing hf CLI..."
    curl -LsSf https://hf.co/cli/install.sh | bash -s

    export PATH="$HOME/.local/bin:$PATH"

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

    success "Shell config updated — run: source $rc_file"
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
    configure_shell

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "Bootstrap complete!"
    echo ""
    echo "  Next steps:"
    echo "    hf auth login           # đăng nhập HF account"
    echo "    uv --version            # kiểm tra uv"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
