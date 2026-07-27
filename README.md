# 🎨 ComfyUI Automated Setup & Multi-Platform Optimizer

> Bộ công cụ cài đặt tự động ComfyUI tối ưu hóa nâng cao — tự động nhận diện môi trường, sửa lỗi thiếu package, kiểm tra link trước khi tải, tải đa nguồn qua link dự phòng (Mirror Fallback Engine) và xuất báo cáo tổng kết chi tiết.

---

## ✨ Tính Năng Nổi Bật

### 🚀 Cài Đặt & Tự Động Hóa
1. **Dò Tìm Thư Mục ComfyUI Tự Động (`COMFY_BASE`)**
   - Tự động nhận diện ComfyUI tại các môi trường: Google Colab, Kaggle, RunPod, Vast.ai, SageMaker.
   - Tự gộp và xóa thư mục ComfyUI trùng lặp để tiết kiệm đĩa.
   - Hỗ trợ tham số `--comfy-dir <PATH>` hoặc biến môi trường `COMFY_BASE`.

2. **Hiển Thị Thông Tin Máy Chủ Chi Tiết Khi Khởi Động**
   - Ngay khi chạy `bash install.sh`, hệ thống in ra khung đẹp gồm: OS/Kernel, CPU, RAM, GPU/VRAM, dung lượng đĩa (cảnh báo đỏ nếu < 20GB), IP công khai, phiên bản Python.

3. **Khung Nhập Civitai Token Với Timeout 5 Phút**
   - Script dừng lại và hiển thị khung nhập token đẹp.
   - Nếu không nhập trong **5 phút**, script tự động đóng.
   - Nếu truyền token qua `--civitai-token`, bỏ qua bước hỏi.

4. **Tự Động Bổ Sung Công Cụ Khi Thiếu**
   - Tự kiểm tra và cài: `aria2c`, `wget`, `curl`, `git`, `ffmpeg`, `libGL`, `libglib`, `jq`, `pip3`.

### 📦 Tải Model Thông Minh
5. **Kiểm Tra Link Sống Trước Khi Tải**
   - Gửi HEAD request nhanh (10 giây) để kiểm tra trạng thái HTTP mỗi link.
   - Link `404/410` → bỏ qua, thử link phụ tiếp theo tự động.
   - Link `401/403` (cần token) → vẫn thử tải vì token đính kèm trong URL.

6. **Cơ Chế Tải Đa Nguồn & Link Dự Phòng (Multi-Source Mirror Engine)**
   - Tự động sinh link mirror cho Civitai (`civitai.com` ↔ `civitai.red`), HuggingFace (`hf-mirror.com`), GitHub Proxy (`ghproxy.net`).
   - Thử nghiệm qua chuỗi công cụ: `aria2c` → `wget` → `curl` → `python urllib`.

7. **Dọn Dẹp Tự Động Pip Cache Sau Cài Đặt**
   - Giải phóng 5–8 GB đĩa rác sau mỗi lần cài xong.

### 🔧 Bảo Trì & Sửa Lỗi
8. **Tự Động Sửa Lỗi Thiếu Package cho Custom Nodes (`bash fix_nodes.sh`)**
   - Quét toàn bộ `custom_nodes/`, cài lại `requirements.txt` từng node.
   - Kiểm tra import Python, phát hiện và cài tự động package đang thiếu.
   - In báo cáo tổng kết: bao nhiêu node OK, bao nhiêu vẫn còn lỗi.

9. **Khởi Động Lại An Toàn (`bash reload.sh`)**
   - Tự diệt tiến trình cũ, xả cổng 8188 bị nghẽn.
   - Tự tạo Cloudflare Tunnel → in ra link HTTPS truy cập từ xa.

10. **Sao Lưu Ảnh Real-time về Google Drive (`gdrive_sync.sh`)**
    - Tự upload ảnh vừa sinh từ ComfyUI vào Google Drive liên tục.

11. **Báo Cáo Tổng Kết Chi Tiết Sau Khi Hoàn Tất**
    - Xuất ra `SETUP_REPORT.md` (Markdown đẹp) và `setup_report.json` (máy đọc).
    - Đo thời gian thực thi, tỷ lệ sai số, danh sách file tải qua Mirror / thất bại.

---

## 📁 Cấu Trúc Dự Án

```
.
├── install.sh              # Entry Point chính - Hỗ trợ CLI flags đầy đủ
├── install_nodes.sh        # Chỉ cài Custom Nodes (nhẹ ~6GB, cài trước để tránh tràn đĩa)
├── install_models.sh       # Chỉ tải Models
├── fix_nodes.sh            # Tự động sửa lỗi thiếu package cho mọi Custom Node
├── reload.sh               # Khởi động lại ComfyUI an toàn + tạo link tunnel
│
├── config/
│   ├── models_list.csv         # Danh sách model với link chính gốc
│   ├── models_backup_list.csv  # Link dự phòng (Civitai.red, HF Mirror, GHProxy)
│   └── nodes_list.txt          # Danh sách Custom Nodes kèm mô tả chi tiết
│
├── colab/
│   └── comfyui_colab.ipynb     # Notebook Google Colab - Tích hợp đầy đủ tính năng
│
└── scripts/
    ├── common.sh           # Module dùng chung: Mirror engine, URL checker, Downloader
    ├── 01_env_setup.sh     # Stage 01: Môi trường Python/Torch + thư viện hệ thống
    ├── 02_comfy_core.sh    # Stage 02: Clone/Pull ComfyUI Core
    ├── 03_nodes_setup.sh   # Stage 03: Clone Custom Nodes với Git Mirror Fallback
    ├── 04_models_dl.sh     # Stage 04: Tải Models với Multi-Source Fallback
    ├── 05_manifest.sh      # Stage 05: Báo cáo tổng kết Markdown + JSON
    └── 06_gdrive_sync.sh   # Stage 06: Đồng bộ ảnh về Google Drive
```

---

## 🚀 Hướng Dẫn Sử Dụng

### ▶️ Cài Đặt Đầy Đủ (Khuyến Nghị)
```bash
# Bước 1: Tải bộ script
git clone https://github.com/hung187/comfyui-setup1.git && cd comfyui-setup1

# Bước 2: Chạy cài đặt - Script sẽ hỏi token rồi tự làm tất cả
bash install.sh
```

### ⚡ Cài 2 Bước Để Tránh Tràn Đĩa (Khuyến Nghị Cho Server 100GB)
```bash
# Bước 1: Cài Custom Nodes trước (~6GB)
bash install_nodes.sh

# Bước 2: Tải Models sau (tiết kiệm đĩa tối ưu)
bash install_models.sh
```

### 🔧 Các Lệnh Tiện Ích
```bash
# Khởi động lại ComfyUI (sau khi server bị reset/timeout)
bash reload.sh

# Tự động sửa lỗi thiếu package cho tất cả Custom Nodes
bash fix_nodes.sh

# Chỉ tải Models mà không cài lại Nodes
bash install.sh --only-models

# Chế độ kiểm tra nhanh (không tải file nặng - để test script)
bash install.sh --dry-run

# Tắt kiểm tra SSL khi mạng chập chờn
bash install.sh --no-ssl-verify

# Chỉ định thư mục và token qua tham số CLI
bash install.sh --comfy-dir /workspace/ComfyUI --civitai-token YOUR_TOKEN
```

### ☁️ Chạy Trên Google Colab
Mở file **[`colab/comfyui_colab.ipynb`](colab/comfyui_colab.ipynb)** trên Google Colab rồi bấm **Runtime → Run all**.

---

## ⚙️ Các Tham Số CLI Đầy Đủ

| Tham Số | Mô Tả |
|---|---|
| `--comfy-dir <PATH>` | Chỉ định thủ công thư mục ComfyUI |
| `--civitai-token <TOKEN>` | Truyền token Civitai qua CLI (bỏ qua khung hỏi) |
| `--only-nodes` | Chỉ cài ComfyUI + Custom Nodes |
| `--only-models` | Chỉ tải Models |
| `--gdrive` | Bật tự động sync ảnh về Google Drive |
| `--gdrive-folder <DIR>` | Tên thư mục trên Google Drive |
| `--dry-run` | Chế độ kiểm tra nhanh, không tải file nặng |
| `--no-ssl-verify` | Bỏ qua kiểm tra SSL |
| `--reload` | Tắt ComfyUI cũ và khởi động lại |
| `--help` | Hiển thị menu hướng dẫn |

---

## 💡 Lưu Ý Quan Trọng

> **Ổ đĩa 100GB**: Luôn cài Custom Nodes trước (`bash install_nodes.sh`) rồi mới tải Models (`bash install_models.sh`) để tránh tràn đĩa khi tải.

> **Token Civitai**: Lấy tại [civitai.com/user/account](https://civitai.com/user/account) → mục **API Keys**. Token cần thiết để tải hầu hết Models, LoRAs trong danh sách.

> **Lỗi Custom Nodes**: Nếu sau khi cài xong mà một số node bị đỏ lỗi trong ComfyUI, chỉ cần chạy `bash fix_nodes.sh` để tự động sửa toàn bộ.
