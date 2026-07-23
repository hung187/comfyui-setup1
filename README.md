# ComfyUI Automated Setup & Multi-Platform Optimizer

Bộ công cụ cài đặt tự động ComfyUI tối ưu hóa nâng cao, tự động nhận diện môi trường (Cloud Server đến PC cá nhân), tự bổ sung công cụ thiếu, tải đa nguồn qua link dự phòng (Mirror Fallback Engine) và xuất báo cáo tổng kết chi tiết thời gian & sai số.

## ✨ Tính Năng Nổi Bật

1. **Dò Tìm Thư Mục ComfyUI Tự Động (`COMFY_BASE`)**:
   - Tự động nhận diện ComfyUI tại các môi trường Server/Cloud: Google Colab, Kaggle, RunPod, Vast.ai, SageMaker.
   - Ưu tiên chọn đúng vị trí đã có file cài đặt (`main.py`, `folder_paths.py`).
   - Hỗ trợ tham số `--comfy-dir <PATH>` hoặc biến môi trường `COMFY_BASE`.

2. **Tự Động Bổ Sung Công Cụ Khi Thiếu (Auto Tool Installer)**:
   - Tự động kiểm tra và tải/cài đặt các công cụ thiếu: `aria2c`, `wget`, `curl`, `git`, `jq`, `sha256sum`, `pip3`, `python3`.
   - Sử dụng package manager của hệ thống (`apt-get`) hoặc tự động dùng công cụ tải thay thế phù hợp.

3. **Cơ Chế Tải Đa Nguồn & Link Dự Phòng (Multi-Source Mirror Engine)**:
   - Khi tải model từ Link Chính bị lỗi (404, 401, timeout, hash sai), hệ thống tự động chuyển sang Link Phụ (Mirror).
   - Tự động sinh link mirror cho Civitai (`civitai.com` ↔ `civitai.red`), HuggingFace (`hf-mirror.com`), GitHub Proxy (`ghproxy.net`).
   - Thử nghiệm qua chuỗi công cụ tải: `aria2c` → `wget` → `curl` → `python urllib`.

4. **Báo Cáo Tối Ưu Tải Xuống Chi Tiết (Detailed Metrics & Error Report)**:
   - Đo tổng thời gian thực thi chính xác từng giây/phút.
   - Thống kê tỷ lệ sai số / lỗi (Error Rate %).
   - Liệt kê chi tiết các file đã phải tải qua **Link Phụ (Mirror)** và các file **Tải Thất Bại (Failed)**.
   - Xuất dữ liệu báo cáo ra file Markdown (`SETUP_REPORT.md`) và file JSON máy đọc (`setup_report.json`).

---

## 📁 Cấu Trúc Dự Án

```
.
├── install.sh             # Main Entry Point hỗ trợ CLI flags
├── config/
│   ├── models_list.csv    # Danh sách model (hỗ trợ format 4 cột & 5 cột link dự phòng)
│   └── nodes_list.txt     # Danh sách custom nodes
└── scripts/
    ├── common.sh          # Module dùng chung: Auto path, Tool installer, Mirror engine
    ├── 01_env_setup.sh    # Stage 01: Cài đặt công cụ & môi trường Python/Torch
    ├── 02_comfy_core.sh    # Stage 02: Validation Civitai Token & Clone/Pull ComfyUI Core
    ├── 03_nodes_setup.sh  # Stage 03: Clone Custom Nodes với Git Mirror Fallback
    ├── 04_models_dl.sh     # Stage 04: Tải Models với Multi-Source Fallback
    └── 05_manifest.sh     # Stage 05: Tính tổng thời gian, tỷ lệ sai số, xuất báo cáo Markdown/JSON
```

---

## 🚀 Hướng Dẫn Sử Dụng

### 1. Chạy Cài Đặt Mặc Định:
```bash
bash install.sh
```

### 2. Chạy Với Tham Số CLI:
```bash
# Chỉ định vị trí ComfyUI & Token Civitai
bash install.sh --comfy-dir /workspace/ComfyUI --civitai-token YOUR_CIVITAI_TOKEN

# Chế độ kiểm tra nhanh DRY_RUN (không tải file nặng)
bash install.sh --dry-run

# Tắt kiểm tra SSL khi mạng chập chờn
bash install.sh --no-ssl-verify
```
