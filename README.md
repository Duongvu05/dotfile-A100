# dotfile-A100

Dotfiles & startup script cho RunAI pod (DGX A100). Giải quyết vấn đề pod là ephemeral — mỗi lần restart mất sạch cài đặt — bằng cách lưu state vào persistent volume `/home/data/` và chạy một lệnh duy nhất để khôi phục.

## Kiến trúc

```
Laptop ──SSH──► localgpu ──SSH──► RunAI Pod
                                  (100.x.x.x via Tailscale)
```

Kết nối SSH qua **Tailscale** — IP cố định, không đổi dù pod restart bao nhiêu lần.

## Lần đầu tiên (install)

```bash
# 1. Clone repo vào persistent volume
cd /home/data
git clone git@github.com:Duongvu05/dotfile-A100.git

# 2. Thêm SSH public key của localgpu vào authorized_keys
echo "ssh-ed25519 AAAA...KEY..." > /home/data/.ssh_authorized_keys

# 3. Lưu Tailscale auth key (lấy tại tailscale.com/settings/keys)
echo "tskey-auth-..." > /home/data/.tailscale_authkey

# 4. Chạy install (~ 3 phút)
bash /home/data/dotfile-A100/setup.sh install
```

Install sẽ tự động cài:

| Tool | Mục đích |
|---|---|
| `uv` | Python package manager (nhanh hơn pip) |
| `huggingface-cli` + `hf` | Download/upload model từ HuggingFace |
| `hf_xet` | HF xet transfer protocol |
| `nvitop` | GPU monitor thời gian thực |
| `pm2` + Node.js | Process manager — giữ job chạy nền qua restart |

Sau install, thêm SSH public key của pod vào GitHub:

```
https://github.com/settings/ssh/new
```

## Mỗi lần pod restart

```bash
bash /home/data/dotfile-A100/setup.sh
```

Hoặc dùng Makefile:

```bash
cd /home/data/dotfile-A100 && make startup
```

Startup sẽ khôi phục theo thứ tự:

1. **sshd** — restore authorized_keys + GitHub SSH key
2. **Tools** — activate uv, nvm, node, pm2
3. **PM2** — resurrect các job đã lưu
4. **Tailscale** — kết nối VPN, lấy IP cố định

Output mẫu:

```
[OK]    sshd started
[OK]    Tools: uv=0.5.x, node=v20.x, pm2=5.x
[OK]    PM2 jobs resurrected
[OK]    Tailscale: 100.x.x.x
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[OK]    STARTUP DONE — ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Kết nối từ localgpu

```bash
# ~/.ssh/config trên localgpu
Host runai-pod
  HostName 100.x.x.x      # IP Tailscale của pod (cố định)
  User root
  IdentityFile ~/.ssh/id_ed25519
```

```bash
ssh runai-pod
```

## Lệnh thường dùng trên pod

```bash
nvitop                          # GPU monitor
pm2 list                        # Xem jobs đang chạy
pm2 logs                        # Xem logs
tailscale ip -4                 # Xem IP Tailscale hiện tại
hf auth login                   # Đăng nhập HuggingFace
ssh -T git@github.com           # Test GitHub SSH
```

## Files quan trọng trên /home/data/

| Path | Nội dung |
|---|---|
| `/home/data/.tailscale_authkey` | Tailscale auth key (**không commit**) |
| `/home/data/.ssh_authorized_keys` | SSH public keys được phép truy cập |
| `/home/data/.ssh/id_ed25519_github` | GitHub SSH key của pod |
| `/home/data/tailscale-state.json` | Tailscale state (giữ IP cố định) |
| `/home/data/.pm2/` | PM2 state — job list qua restart |
