# dotfile-A100

Dotfiles & startup script cho **RunAI pod (DGX A100)**. Giải quyết vấn đề pod là ephemeral — mỗi lần restart mất sạch cài đặt — bằng cách lưu toàn bộ state vào persistent volume `/home/data/` và khôi phục bằng một lệnh duy nhất.

## Kiến trúc

```
Laptop (nhà/VP) ─── Tailscale ───► Máy bàn (VP, subnet router) ───► RunAI web UI
                                                  │
                                                  └── Tailscale ───► RunAI Pod
                                                                    (IP cố định)
```

- **RunAI pod** kết nối qua Tailscale — IP cố định, không đổi dù pod restart
- **Máy bàn văn phòng** làm Tailscale subnet router — truy cập RunAI web UI từ nhà không cần VPN trường
- **Laptop** truy cập cả pod lẫn web UI từ bất kỳ đâu qua Tailscale

---

## Lần đầu tiên (install)

```bash
# 1. Clone repo vào persistent volume
cd /home/data
git clone git@github.com:Duongvu05/dotfile-A100.git

# 2. Thêm SSH public key của máy cần truy cập pod
echo "ssh-ed25519 AAAA...KEY..." > /home/data/.ssh_authorized_keys

# 3. Lưu Tailscale auth key (lấy tại tailscale.com/settings/keys)
echo "tskey-auth-..." > /home/data/.tailscale_authkey

# 4. Chạy install (~3 phút)
bash /home/data/dotfile-A100/setup.sh install
```

Sau install, thêm SSH public key của pod vào GitHub:
```
https://github.com/settings/ssh/new
```

### Công cụ được cài tự động

| Tool | Mục đích |
|---|---|
| `uv` | Python package manager (nhanh hơn pip) |
| `huggingface-cli` + `hf` | Download/upload model từ HuggingFace |
| `hf_xet` | HF xet transfer protocol |
| `nvitop` | GPU monitor thời gian thực |
| `pm2` + Node.js | Process manager — giữ job chạy qua restart |
| `tailscale` | VPN — SSH vào pod từ bất kỳ đâu |

---

## Mỗi lần pod restart

```bash
bash /home/data/dotfile-A100/setup.sh
# hoặc
cd /home/data/dotfile-A100 && make startup
```

Startup khôi phục theo thứ tự:

1. **sshd** — restore `authorized_keys` + GitHub SSH key
2. **Tools** — activate uv, nvm, node, pm2
3. **PM2** — resurrect các job đã lưu
4. **Tailscale** — kết nối VPN, lấy IP cố định
5. **Reverse tunnel** — mở port 2222 trên worker để SSH vào pod

Output mẫu:
```
[OK]    sshd started
[OK]    Tools: uv=0.5.x, node=v20.x, pm2=5.x
[OK]    PM2 jobs resurrected
[OK]    Tailscale: 100.x.x.x
[OK]    Reverse tunnel → vungocduong@100.89.187.1 (trên worker: ssh -p 2222 root@localhost)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[OK]    STARTUP DONE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## SSH vào pod

SSH thẳng vào Tailscale IP của pod **không hoạt động** — tailscaled trên pod chạy userspace-networking (container không có `/dev/net/tun`), inbound TCP chỉ đi được qua DERP relay và bị timeout. Startup script tự mở **reverse tunnel** sang worker thay thế:

```
Pod ──(reverse tunnel, port 2222)──► bailab-worker-61 (100.89.187.1)
```

Từ worker (hoặc máy đã SSH vào worker):

```bash
ssh -p 2222 root@localhost
```

Hoặc trong `~/.ssh/config` trên worker:

```
Host runai-pod
  HostName localhost
  Port 2222
  User root
```

Tunnel auth bằng Tailscale SSH (tailnet identity) nên không cần thêm key. Nếu tunnel đứt, vòng lặp trong `start_reverse_tunnel` tự reconnect sau 5s; log tại `/home/data/tunnel.log`.

> Public key của máy cần vào pod vẫn phải có trong `/home/data/.ssh_authorized_keys` (sshd trên pod xác thực bằng key như bình thường).

---

## Truy cập RunAI web UI từ nhà

Khi pod dừng, cần vào web UI để resubmit job. Setup máy bàn văn phòng làm **subnet router** để truy cập mạng nội bộ qua Tailscale — không cần SSH tunnel hay VPN trường.

### Cài đặt 1 lần trên máy bàn văn phòng

```bash
# Máy bàn dùng laptop làm exit node để có internet,
# đồng thời expose subnet nội bộ cho các máy khác
sudo tailscale up \
  --advertise-routes=<office-subnet>/24 \
  --accept-routes \
  --exit-node=<tailscale-ip-laptop> \
  --accept-dns=false
```

Approve subnet route trên [Tailscale admin console](https://login.tailscale.com/admin/machines):
→ Tìm máy bàn → **Edit route settings** → bật `<office-subnet>/24`

### Trên laptop (1 lần)

```bash
tailscale set --accept-routes
```

### Kết quả

Từ nhà mở browser vào địa chỉ RunAI nội bộ — không cần toggle hay SSH tunnel gì thêm.

```
Traffic đến office subnet  ──► máy bàn VP  ──► RunAI web UI   ✓
Traffic thông thường        ──► thẳng internet (không qua VP)  ✓
```

> **Lưu ý:** Máy bàn văn phòng phải đang bật.

---

## Files quan trọng trên `/home/data/`

| Path | Nội dung | Git-ignored |
|---|---|---|
| `.tailscale_authkey` | Tailscale auth key | ✓ |
| `.ssh_authorized_keys` | SSH public keys được phép vào pod | ✓ |
| `.ssh/id_ed25519_github` | GitHub SSH key của pod | — |
| `tailscale-state.json` | Tailscale state (giữ IP cố định qua restart) | — |
| `tunnel.log` | Log của reverse SSH tunnel sang worker | — |
| `.pm2/` | PM2 job list và state | — |
| `.local/bin/` | uv + tools binaries | — |
| `.nvm/` | Node Version Manager | — |

---

## Lệnh thường dùng trên pod

```bash
nvitop                    # GPU monitor thời gian thực
pm2 list                  # Xem jobs đang chạy
pm2 logs                  # Xem logs
pm2 save                  # Lưu state để resurrect sau restart
tailscale ip -4           # IP Tailscale hiện tại của pod
hf auth login             # Đăng nhập HuggingFace
ssh -T git@github.com     # Kiểm tra GitHub SSH
```
