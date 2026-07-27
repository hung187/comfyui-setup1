# AGENTS.md — Hướng Dẫn Cho AI Agent Làm Việc Với Project comfyui-setup1

> Tài liệu này dành cho AI agents (Antigravity, Gemini, Claude, v.v.) để hiểu đúng kiến trúc, quy tắc đặt tên, luồng thực thi và các điểm cần chú ý khi chỉnh sửa project này.

---

## 1. Mục Đích Dự Án

Bộ script Bash **hoàn toàn tự động** cài đặt ComfyUI (phần mềm tạo ảnh AI) trên:
- **Google Colab / Kaggle** (GPU cloud miễn phí)
- **RunPod / Vast.ai / SageMaker** (GPU server thuê)
- **Máy tính cá nhân Linux** với GPU Nvidia

Tập trung vào nhu cầu **vẽ ảnh Anime 2D (Illustrious XL / Pony)** và **dựng khối 3D (TRELLIS2)**.

---

## 2. Cấu Trúc File & Trách Nhiệm

```
comfyui-setup1/
│
├── install.sh              ← Entry point CHÍNH — tổng hợp tất cả stages
├── install_nodes.sh        ← Chỉ cài Nodes (Stage 01+02+03+05+06) — <10GB
├── install_models.sh       ← Chỉ tải Models (Stage 01+04+05) — cần token
├── fix_nodes.sh            ← Tự động sửa lỗi thiếu package cho Custom Nodes
├── reload.sh               ← Khởi động lại ComfyUI + Cloudflare Tunnel
│
├── config/
│   ├── models_list.csv         ← Link GỐC (1 link/model) — đây là nguồn sự thật
│   ├── models_backup_list.csv  ← Link PHỤ dự phòng (cùng key = đường dẫn file)
│   └── nodes_list.txt          ← Danh sách custom nodes (git URL)
│
├── scripts/
│   ├── common.sh           ← Module dùng chung: hàm tiện ích cốt lõi
│   ├── 01_env_setup.sh     ← Stage 01: Cài công cụ hệ thống + PyTorch
│   ├── 02_comfy_core.sh    ← Stage 02: Mã hóa token + Clone ComfyUI
│   ├── 03_nodes_setup.sh   ← Stage 03: Clone Custom Nodes + pip requirements
│   ├── 04_models_dl.sh     ← Stage 04: Tải Models (multi-mirror fallback)
│   ├── 05_manifest.sh      ← Stage 05: Báo cáo tổng kết Markdown + JSON
│   └── 06_gdrive_sync.sh   ← Stage 06: Đồng bộ ảnh về Google Drive
│
└── colab/
    └── comfyui_colab.ipynb ← Notebook Google Colab 8-cell đầy đủ tính năng
```

---

## 3. Quy Tắc Quan Trọng Khi Chỉnh Sửa

### 3.1 Luồng Thực Thi & Phụ Thuộc

```
install.sh
  ├── source scripts/common.sh       ← PHẢI load TRƯỚC TẤT CẢ
  ├── show_server_info()             ← In thông tin máy chủ
  ├── prompt_civitai_token()         ← Hỏi token (timeout 5 phút)
  ├── source scripts/01_env_setup.sh
  ├── source scripts/02_comfy_core.sh
  ├── source scripts/03_nodes_setup.sh
  ├── source scripts/04_models_dl.sh
  ├── source scripts/05_manifest.sh
  └── source scripts/06_gdrive_sync.sh
```

> ⚠️ **KHÔNG bao giờ** thêm lệnh hỏi `CIVITAI_TOKEN` lần thứ hai vào trong các stage scripts. `install.sh` đã xử lý điều này ở đầu qua `prompt_civitai_token()`.

### 3.2 Quy Tắc Biến Môi Trường (Export)

Các biến sau được khởi tạo trong `common.sh → init_runtime_env()` và phải được `export` để con process Python đọc được:

| Biến | Ý nghĩa | Nơi gán |
|---|---|---|
| `COMFY_BASE` | Đường dẫn thư mục ComfyUI | `common.sh` |
| `MODELS` | `$COMFY_BASE/models` | `common.sh` |
| `CUSTOM_NODES` | `$COMFY_BASE/custom_nodes` | `common.sh` |
| `CIVITAI_TOKEN` | Token thô của người dùng | `install.sh` |
| `ENCODED_TOKEN` | Token đã URL-encode | `02_comfy_core.sh` |
| `START_TIME` | Unix timestamp lúc bắt đầu | `install.sh` |
| `TIME_STR` | Chuỗi thời gian ("2m 30s") | `05_manifest.sh` ← phải `export TIME_STR="$time_str"` |
| `LOG_FILE` | File log sự kiện tải | `common.sh` |
| `REPORT_FILE` | Đường dẫn báo cáo Markdown | `common.sh` |
| `REPORT_JSON` | Đường dẫn báo cáo JSON | `common.sh` |
| `DRY_RUN` | =1 để test nhanh không tải | CLI flag |

### 3.3 Format File Cấu Hình

**`config/models_list.csv`** (link chính gốc):
```
URL_CHINH|$MODELS/DUONG_DAN_LUU|Mo ta|[sha256_tuy_chon]
```

**`config/models_backup_list.csv`** (link phụ dự phòng):
```
$MODELS/DUONG_DAN_LUU|LINK_PHU_1|LINK_PHU_2|LINK_PHU_3
```
> ⚠️ Key của backup_map là **đường dẫn file** (cột 1 của backup = cột 2 của models_list). Phải khớp chính xác tuyệt đối, kể cả `$MODELS/...`.

**`config/nodes_list.txt`** (custom nodes):
```
URL_GIT|$CUSTOM_NODES/TEN_THU_MUC|Ten hien thi
```

### 3.4 Quy Tắc Màu Sắc Terminal

```bash
RED='\033[0;31m'      # Lỗi nghiêm trọng
GREEN='\033[0;32m'    # Thành công
YELLOW='\033[0;33m'   # Cảnh báo / Bỏ qua
BLUE='\033[0;34m'     # Thông tin / đang thực hiện
MAGENTA='\033[0;35m'  # Header section / khung đẹp
CYAN='\033[0;36m'     # Tiến trình phụ / đang kiểm tra
NC='\033[0m'          # Reset màu
```

---

## 4. Các Hàm Quan Trọng Trong `common.sh`

### `init_runtime_env()`
- Gọi đầu tiên trong mỗi stage script
- Tự phát hiện `COMFY_BASE`, `MODELS`, `CUSTOM_NODES`
- Khởi tạo `PIP_BASE_CMD`, `PYTHON_CMD`, `PIP_SSL_OPT`, `CURL_SSL_OPT`

### `check_url_alive(url)`
- Gửi HEAD request (10 giây timeout) kiểm tra link còn sống
- Return 0 = còn sống, Return 1 = chết/lỗi
- **Luôn được gọi trước `exec_download_tool`** trong vòng lặp tải

### `download_model_smart(primary_url, alt_urls, output_path, description, sha256)`
- Multi-source fallback: thử lần lượt primary → alt_urls
- Ghi log sự kiện vào `$LOG_FILE` với format: `timestamp|LEVEL|data`
- LEVEL: `OK_PRIMARY`, `OK_MIRROR`, `SKIP`, `FAIL`, `DEAD_LINK`
- Kiểm tra hash SHA256 nếu được cung cấp

### `clone_or_pull(url, path, desc)`
- Clone git repo mới hoặc `git pull` nếu đã tồn tại
- Hỗ trợ GitHub proxy fallback khi mạng chậm

### `ensure_tool_installed(cmd, pkg)`
- Kiểm tra tool có sẵn không, nếu thiếu thì cài qua `apt-get`
- Ghi tên tool vào `AUTO_INSTALLED_TOOLS[]` để báo cáo cuối

### `check_disk_space()`
- Cảnh báo màu đỏ nếu đĩa trống < 20GB
- Tự động gọi sau Stage 01

### `resolve_config_value(str)`
- Thay thế `$MODELS`, `$CUSTOM_NODES`, `$ENCODED_TOKEN` trong chuỗi

---

## 5. Các Custom Nodes Đã Chọn & Lý Do

| Node | Tác dụng chính |
|---|---|
| ComfyUI Manager | Quản lý nodes/models qua UI |
| ControlNet Aux | Tiền xử lý OpenPose/Canny/Depth |
| IP-Adapter Plus | Copy phong cách/khuôn mặt từ ảnh |
| WAS Node Suite | 100+ node xử lý ảnh đa năng |
| KJNodes | Animation, mask, batch utilities |
| rgthree | Tối ưu UI/workflow |
| Inpaint Nodes | Sửa chi tiết / inpainting |
| Easy Use | Wildcard, simplified samplers |
| LayerStyle | Blend mode, shadow, typography |
| IF AI Tools | Tự động viết Prompt bằng LLM |
| Custom Scripts | Autocomplete prompt, preview |
| Cloud Manager | Kết nối cloud storage |
| Ultimate SD Upscale | Upscale 4x-8x tile-based |
| TRELLIS2 | Ảnh 2D → Mô hình 3D |

> ❌ **KHÔNG thêm lại**: AnimateDiff, VideoHelperSuite, N-Sidebar (đã xóa để tiết kiệm ~30GB)

---

## 6. Danh Sách Model Theo Nhóm

### Checkpoints (~5–7 GB mỗi file)
- `oneObsession_v22.safetensors` — Checkpoint **chủ lực** Illustrious
- `illustriousXL20_v20.safetensors` — Base Illustrious gốc
- `ultimateHentaiAnimeRXTRexAnime_rxV1.safetensors` — NSFW chuyên sâu

### TRELLIS2 (Image → 3D, cần cả 4 file)
- `dino_v3_vit_l.safetensors` (clip_vision)
- `trellis_2_shape_vae_bf16.safetensors` (vae)
- `trellis_2_texture_vae_bf16.safetensors` (vae)
- `trellis_2_bf16.safetensors` (diffusion_models)

### LoRA (phân loại theo subfolder)
- `Quality/` — Cải thiện chất lượng ảnh tổng thể
- `Face/` — Biểu cảm khuôn mặt (ahegao...)
- `Hands/` — Tay người đẹp hơn
- `Character/` — Nhân vật cụ thể (game characters)
- `Style/` — Phong cách vẽ (FComic, Anime, HEN-GEN...)
- `Effect/` — Hiệu ứng da bóng, mồ hôi
- `Pose/` — Tư thế cơ thể NSFW

> ❌ **KHÔNG thêm**: FLUX.2 models (quá nặng 9GB+, không phù hợp nhu cầu Anime/3D)

---

## 7. Ràng Buộc Đĩa Cứng

- **Giới hạn**: ~100 GB tổng (môi trường cloud container)
- **Thực tế còn lại**: ~35–40 GB sau khi cài đầy đủ
- **Quy tắc khi đề xuất thêm model mới**:
  1. Ước tính dung lượng file trước
  2. Đề nghị xóa model cũ tương đương nếu quá giới hạn
  3. Mọi model > 6 GB phải có lý do rõ ràng
- **Tiết kiệm đĩa tự động**: `pip cache purge` được gọi sau Stage 01 và Stage 03

---

## 8. Luồng Token Civitai

```
install.sh
  └── prompt_civitai_token()     ← Hỏi token với timeout 5 phút, khung vàng đẹp
        └── export CIVITAI_TOKEN

scripts/02_comfy_core.sh
  └── run_stage_02()
        ├── URL-encode CIVITAI_TOKEN → ENCODED_TOKEN
        └── export ENCODED_TOKEN

config/models_list.csv
  └── https://civitai.com/...?token=$ENCODED_TOKEN   ← dùng $ENCODED_TOKEN

scripts/common.sh → resolve_config_value()
  └── Thay $ENCODED_TOKEN bằng giá trị thực khi đọc CSV
```

---

## 9. Các Điểm Hay Bị Sai Khi Sửa Code

| Tình huống | Cần chú ý |
|---|---|
| Thêm thư mục LoRA mới | Phải thêm cả vào `mkdir` trong `04_models_dl.sh` |
| Thêm model mới vào CSV | Phải thêm cả vào `models_list.csv` (link gốc) **và** `models_backup_list.csv` (link phụ) với cùng `$MODELS/...` key |
| Thêm tính năng log mới | Dùng `log_event "LEVEL" "data"` từ `common.sh`, không tự `echo` vào LOG_FILE |
| Sửa báo cáo thời gian | Phải `export TIME_STR="$time_str"` trước khi gọi Python heredoc trong `05_manifest.sh` |
| Xóa custom node | Phải xóa ở `config/nodes_list.txt`, không xóa thủ công thư mục |
| Thêm CLI flag mới | Phải thêm vào cả `install.sh`, `install_nodes.sh`, `install_models.sh` (3 entry points) |

---

## 10. Cách Test Nhanh (Không Tải File Nặng)

```bash
# Chạy dry-run để test logic mà không tải PyTorch hay Models
bash install.sh --dry-run

# Test chỉ nodes (nhanh hơn)
bash install_nodes.sh --dry-run

# Kiểm tra cú pháp tất cả scripts
bash -n scripts/common.sh
bash -n scripts/01_env_setup.sh
bash -n scripts/02_comfy_core.sh
bash -n scripts/03_nodes_setup.sh
bash -n scripts/04_models_dl.sh
bash -n scripts/05_manifest.sh

# Sửa lỗi package sau khi cài
bash fix_nodes.sh
```

---

## 11. Quy Trình Git

```bash
# Sau khi sửa code xong luôn chạy syntax check trước khi commit
bash -n scripts/*.sh

# Commit với message rõ ràng tiếng Anh
git add . && git commit -m "Fix: mô tả ngắn gọn thay đổi"

# Push lên GitHub (user tự làm thủ công)
git push origin main
```

---

## 12. Mục Tiêu Phát Triển Tiếp Theo (Backlog)

- [ ] Thêm Workflow mẫu JSON cho Illustrious và TRELLIS2 vào `workflows/`
- [ ] Thêm script `check.sh` báo cáo trạng thái server nhanh (GPU, disk, process)
- [ ] Tích hợp xác minh SHA256 cho tất cả model trong `models_list.csv`
- [ ] Hỗ trợ tự động cập nhật toàn bộ LoRA mới nhất từ Civitai API

---

*Cập nhật lần cuối: 2026-07-27 — Phiên bản kiến trúc: Stage-based modular (01→06)*
