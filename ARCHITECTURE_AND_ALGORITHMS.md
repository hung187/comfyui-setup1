# 🔬 BÁO CÁO ĐẠI PHẪU THUẬT THUẬT TOÁN VÀ KIẾN TRÚC VẬN HÀNH (FOR CHATGPT / AI ASSISTANTS)

> **Dự án**: `comfyui-setup1`
> **Mục đích**: Bộ script Bash & Python mô-đun hóa, hoàn toàn tự động triển khai, tối ưu hóa đĩa cứng và khôi phục sự cố cho **ComfyUI** trên Linux Server / GPU Cloud (RunPod, Vast.ai, Google Colab, Kaggle, SageMaker, Local Linux).
> **Lĩnh vực ứng dụng chính**: Vẽ ảnh Anime 2D (Illustrious XL, Pony) & Dựng mô hình 3D từ ảnh 2D (TRELLIS2).

---

## 🏗️ 1. TỔNG QUAN KIẾN TRÚC HỆ THỐNG (SYSTEM ARCHITECTURE)

Dự án tuân theo mô hình **Stage-based Modular Architecture** (Chạy theo từng Giai đoạn từ 01 ➔ 06). Mọi stage được quản lý thông qua Entrypoint chính `install.sh` hoặc chạy độc lập qua các sub-scripts:

```
comfyui-setup1/
├── install.sh              ← Entrypoint chính
├── install_nodes.sh        ← Cài đặt ComfyUI Core + Custom Nodes (<6GB)
├── install_models.sh       ← Tải 42 AI Models
├── fix_nodes.sh            ← Tự động sửa lỗi thiếu package cho Custom Nodes
├── reload.sh               ← Khởi động lại ComfyUI & tạo Cloudflare Tunnel
├── config/
│   ├── models_list.csv         ← Link chính gốc (1 link/model)
│   ├── models_backup_list.csv  ← Link dự phòng HuggingFace/GitHub (Khớp key 1-1)
│   └── nodes_list.txt          ← Danh sách Custom Nodes
└── scripts/
    ├── common.sh           ← Module dùng chung (Chứa các động cơ chính)
    ├── 01_env_setup.sh     ← Stage 01: Cài công cụ & PyTorch
    ├── 02_comfy_core.sh    ← Stage 02: Token Civitai & Clone ComfyUI
    ├── 03_nodes_setup.sh   ← Stage 03: Clone Nodes & pip requirements
    ├── 04_models_dl.sh     ← Stage 04: Động cơ tải Model Đa Nguồn Nguyên Tử
    ├── 05_manifest.sh      ← Stage 05: Báo cáo Markdown & JSON Manifest
    ├── 06_gdrive_sync.sh   ← Stage 06: Đồng bộ ảnh real-time sang Google Drive
    └── update_mirror_list.sh ← Cập nhật mirror manifest tự động hàng ngày
```

---

## 🧠 2. PHÂN TÍCH CHI TIẾT CÁC THUẬT TOÁN CỐT LÕI (ALGORITHMIC DISSECTION)

### 🔹 Thuật Toán 1: Tự Động Phát Hiện & Gộp Thư Mục Trùng Lặp (`resolve_comfy_base`)
- **Tệp thực thi**: `scripts/common.sh`
- **Bài toán**: Trên môi trường Cloud Container (RunPod, Kaggle, Colab, Vast.ai), ComfyUI có thể nằm ở các đường dẫn khác nhau (`/app/ComfyUI`, `/workspace/ComfyUI`, `/content/ComfyUI`, `$HOME/ComfyUI`...). Việc tồn tại nhiều thư mục gây lãng phí dung lượng đĩa.
- **Cơ chế vận hành**:
  1. Duyệt qua mảng 12+ đường dẫn tiêu chuẩn và quét tìm sự tồn tại của file nhận diện `main.py` hoặc `folder_paths.py`.
  2. Nếu không thấy, sử dụng `find /app /workspace /content /root /opt $HOME -maxdepth 3 -name "main.py"` để quét sâu.
  3. **Thuật toán Consolidate (Gộp đĩa)**: Nếu hệ thống phát hiện > 1 thư mục ComfyUI, nó chọn thư mục đầu tiên làm `primary_target`, sau đó dùng `cp -rn` để gộp toàn bộ dữ liệu `models/`, `custom_nodes/`, `output/` từ các thư mục phụ về thư mục chính, rồi thực hiện `rm -rf` xóa thư mục phụ để giải phóng dung lượng đĩa.

### 🔹 Thuật Toán 2: Xử Lý Token Civitai & Timeout Không Chặn (`prompt_civitai_token`)
- **Tệp thực thi**: `install.sh` & `scripts/02_comfy_core.sh`
- **Bài toán**: Lấy token Civitai để tải model 18+/Early Access mà không làm treo script khi chạy trong môi trường CI/CD hoặc không có người tương tác.
- **Cơ chế vận hành**:
  1. Sử dụng `read -t 300` (timeout 5 phút). Nếu người dùng không nhập, tự động bỏ qua và tiếp tục.
  2. **URL-Encoding**: Chuẩn hóa Token thô bằng cách xóa tiền tố `?` hoặc `token=`, loại bỏ khoảng trắng bằng `tr -d '[:space:]'`, sau đó mã hóa URL bằng `jq -sRr @uri` hoặc `sed`.
  3. **Placeholder Injection**: Chuỗi Token mã hóa (`$ENCODED_TOKEN`) được thay thế động vào biến `$ENCODED_TOKEN` trong CSV qua hàm `resolve_config_value()`.

### 🔹 Thuật Toán 3: Động Cơ Tải Model Đa Nguồn Nguyên Tử & Chống Lỗi HTTP 307 (`download_model_smart` & `exec_download_tool`)
- **Tệp thực thi**: `scripts/common.sh` & `scripts/04_models_dl.sh`
- **Bài toán**: Tải 42 Model AI (tổng ~28GB) từ Civitai/HuggingFace với tỷ lệ thành công 100%, chống đứt mạng, xử lý HTTP 307 Redirect của Cloudflare R2 và không tải lại file đã hoàn tất.

#### 🔑 Các Điểm Kỹ Thuật Đặc Biệt Trong Động Cơ Tải:
1. **User-Agent Impersonation**: Đóng giả trình duyệt Chrome thực sự (`USER_AGENT="Mozilla/5.0 ... Chrome/125.0.0.0"`) trên cả 4 công cụ (`aria2c --user-agent`, `wget --user-agent`, `curl -A`, `urllib Request Headers`) để tránh bị Civitai/Cloudflare chặn 403.
2. **Xử lý HTTP 307 Redirect**: Civitai API chuyển hướng tải về Cloudflare R2 / AWS S3. Sử dụng `curl -L --max-redirs 10` và `wget --max-redirect=10` để tự động nối luồng tải trực tiếp từ CDN storage.
3. **Atomic Resumable Download**: Tất cả công cụ đều ghi vào tệp tạm `.part` và bật chế độ Resume (`aria2c -c`, `wget -c`, `curl -C -`). Chỉ khi file hoàn chỉnh 100% mới thực hiện `mv` để đảm bảo không bao giờ bị dính file rác / hỏng.
4. **Loại Bỏ Mirror Civitai.red**: Toàn bộ mirror `civitai.red` bị chập chờn đã được thay thế 100% bằng **HuggingFace Mirror** (`hf-mirror.com`, `hf.co`) và GitHub proxies (`ghproxy.net`).
5. **State Tracking**: Xuất trạng thái chi tiết theo thời gian thực ra tệp `$COMFY_BASE/download_state.json`.

### 🔹 Thuật Toán 4: Tự Động Phân Tích & Khôi Phục Custom Node (`fix_nodes.sh`)
- **Tệp thực thi**: `fix_nodes.sh`
- **Bài toán**: Khi các Custom Node thiếu thư viện Python, ComfyUI sẽ bị đỏ node hoặc không khởi động được.
- **Cơ chế vận hành**:
  1. Quét từng thư mục trong `custom_nodes/`.
  2. Thực thi `pip3 install -r requirements.txt` cho từng node.
  3. **Python Import Tester**: Khởi chạy script Python ảo test `import` tất cả các file `.py` trong node. Nếu bắt được ngoại lệ `ModuleNotFoundError: No module named 'XYZ'`, nó trích xuất tên module `XYZ` và tự động thực hiện `pip3 install XYZ` ngay lập tức.

### 🔹 Thuật Toán 5: Đồng Bộ Ảnh Real-Time Sang Google Drive (`scripts/06_gdrive_sync.sh`)
- **Tệp thực thi**: `scripts/06_gdrive_sync.sh`
- **Cơ chế 1 (Google Colab)**: Tạo Symlink liên kết mềm `$COMFY_BASE/output` ➔ `/content/drive/MyDrive/ComfyUI_Outputs`.
- **Cơ chế 2 (Linux VPS / Server với rclone)**:
  - Khởi chạy daemon ngầm theo dõi thư mục output bằng `inotifywait -q -e close_write,moved_to`.
  - Ngay khi có file ảnh `.png/.jpg/.webp` được ghi xong, daemon kích hoạt `rclone copy` đẩy file lên Google Drive trong 1-2 giây.
  - Hỗ trợ cơ chế dự phòng **Polling 30s** nếu môi trường thiếu `inotifywait`.

### 🔹 Thuật Toán 6: Cập Nhật Mirror Hàng Ngày & Khóa Tránh Xung Đột (`scripts/update_mirror_list.sh`)
- **Tệp thực thi**: `scripts/update_mirror_list.sh`
- **Cơ chế vận hành**:
  1. Tải file `models_backup_list.csv` mới nhất từ GitHub raw repository.
  2. **Validation**: Kiểm tra file tải về không rỗng, chứa cấu trúc `$MODELS/` hợp lệ, và số dòng >= số dòng hiện tại.
  3. **Atomic Backup**: Sao lưu file cũ thành `models_backup_list.csv.bak_YYYYMMDD` trước khi ghi đè file mới.
  4. **Cron & Flock Locking**: Sử dụng `flock -n /tmp/update_mirror.lock` để đảm bảo Cron job (chạy 03:00 sáng) không bị khởi chạy đè lên nhau khi tiến trình trước chưa kết thúc.

---

## 📁 3. BẢNG TRA CỨU FILE CẤU HÌNH & CHỨC NĂNG

| Tệp Cấu Hình / Script | Chức Năng Cốt Lõi | Định Dạng Dữ Liệu |
|:---|:---|:---|
| `config/models_list.csv` | Nguồn sự thật chứa link Civitai API chính gốc | `URL_CHINH\|$MODELS/DUONG_DAN\|MO_TA\|SHA256` |
| `config/models_backup_list.csv` | Nguồn link phụ dự phòng HuggingFace / GitHub | `$MODELS/DUONG_DAN\|LINK_PHU_1\|LINK_PHU_2\|LINK_PHU_3` |
| `config/nodes_list.txt` | Danh sách Custom Nodes chọn lọc | `URL_GIT\|$CUSTOM_NODES/TEN_THU_MUC\|TEN_HIEN_THI` |
| `.env.example` | Tham số biến môi trường chuẩn | `CIVITAI_TOKEN`, `USER_AGENT`, `MAX_RETRIES`, `TIMEOUT` |
| `download_state.json` | Trạng thái máy đọc theo dõi từng model | JSON object ghi `status` (`completed`/`failed`), `size` |
| `SETUP_REPORT.md` | Báo cáo Markdown tổng kết sau khi chạy | Bảng Markdown chi tiết thời gian, lỗi %, mirror % |

---

## 🎯 4. CÁC QUY TẮC BẮT BUỘC KHI CHỈNH SỬA CODE (FOR CHATGPT)

1. **Khóa Key Đối Soát CSV**: Key đối soát giữa `models_list.csv` và `models_backup_list.csv` là **ĐƯỜNG DẪN FILE ABSOLUTE** (`$MODELS/...`). Khi thêm model mới, phải thêm đúng key này ở cả 2 file.
2. **Không Dùng civitai.red**: Domain `civitai.red` đã sập/lỗi. Mọi link dự phòng cho Civitai phải dùng HuggingFace Mirror hoặc link API Civitai chính thức.
3. **Không Thay Đổi Cú Pháp Output Progress**: Các dòng log format `⬇️  [X/Y] Tải: ...` được parse tự động bởi regex stage 05. Không được tự ý xóa hoặc thay đổi format màu ANSI.
4. **Luôn Giữ Lại User-Agent**: Mọi lệnh HTTP request (curl, wget, aria2c, urllib) phải giữ nguyên `USER_AGENT` Chrome thực sự để không bị ăn lỗi HTTP 403/307 từ Cloudflare.

---
*Tài liệu này được xuất tự động phục vụ mục đích nạp ngữ cảnh hoàn chỉnh cho ChatGPT / LLMs.*
