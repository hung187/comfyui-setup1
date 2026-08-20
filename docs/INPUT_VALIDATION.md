# Input Validation & Preflight Safety Gate Contract

Tài liệu này mô tả chi tiết hợp đồng xác thực dữ liệu đầu vào (Input Validation), cơ chế tiền kiểm an toàn (Preflight Safety Gate) và các hàng rào bảo vệ ranh giới (Boundary Defense-in-Depth) trong dự án `comfyui-setup1`.

---

## 1. Mục Đích & Nguyên Tắc

1. **Chặn sớm (Fail-Early)**: Toàn bộ cấu hình CSV, biến môi trường, đường dẫn lưu, URL, và hash được tiền kiểm toàn diện trước khi thực hiện bất kỳ lệnh tải về, clone git, pip install, di chuyển hoặc xóa dữ liệu nào.
2. **Bảo vệ ranh giới (Defense-in-Depth)**: Trước mỗi thao tác nguy hiểm (`rm`, `mv`, `git clone`, `pip install`), mã nguồn luôn tái kiểm tra tính hợp lệ và an toàn của đối tượng tại thời điểm thực thi (chống TOCTOU).
3. **Một nguồn chân lý (Single Source of Truth)**: Bộ hàm validation nằm tập trung tại `scripts/validation.sh` và được tái sử dụng trực tiếp bởi các stage production và bộ test suite.
4. **Không làm rò rỉ bí mật (Secret Safe)**: URL và token luôn được làm sạch qua hàm `redact_url` trước khi in ra màn hình hoặc ghi vào log/state/report.

---

## 2. Tiêu Chuẩn Đầu Vào & Quy Tắc Kiểm Tra

### 2.1 Đường Dẫn (Paths & Containment)
- **`validate_safe_path(path)`**:
  - Từ chối đường dẫn rỗng, chứa ký tự điều khiển (`\n`, `\r`, `\0`, `\t`) hoặc ký tự shell injection (`;`, `&`, `` ` ``, `$`, `<`, `>`).
  - Phân giải đường dẫn chính tắc qua `realpath`.
  - Nghiêm cấm chọn trực tiếp các thư mục gốc hệ thống làm đích đến phá hủy: `/`, `/root`, `/workspace`, `/app`, `/content`, `/home`, `/etc`, `/var`, `/usr`, `/tmp`, và `$HOME`.
- **`validate_model_destination(path, models_base)`**:
  - Bắt buộc bắt đầu bằng `$MODELS/`.
  - Phải nằm hoàn toàn bên trong cây thư mục chính tắc `$MODELS` (sử dụng `os.path.commonpath`).
  - Nghiêm cấm path traversal (`..`) hoặc trỏ ra ngoài (ví dụ: `/var/tmp/model.safetensors`).
- **`validate_node_destination(path, nodes_base)`**:
  - Bắt buộc bắt đầu bằng `$CUSTOM_NODES/`.
  - Phải nằm hoàn toàn bên trong cây thư mục chính tắc `$CUSTOM_NODES`.

### 2.2 URLs & Domain Trust Classification
- **`validate_url(url)`**:
  - Chỉ chấp nhận giao thức `http://` và `https://` (ưu tiên HTTPS).
  - Từ chối `file://`, `ftp://`, `ssh://`, `javascript:`, `data:`.
  - Từ chối ký tự điều khiển và xuống dòng injection.
- **Tên miền bị cấm (Forbidden Domain)**:
  - Tuyệt đối cấm `civitai.red` và mọi subdomain dạng `*.civitai.red` (dùng suffix boundary chính xác, không dùng substring đơn giản).
- **Phân loại độ tin cậy (Source Trust Classes)**:
  - `OFFICIAL_FIRST_PARTY`: `civitai.com`, `*.civitai.com`, `huggingface.co`, `*.huggingface.co`, `hf.co`, `*.hf.co`, `github.com`, `*.github.com`, `*.githubusercontent.com`.
  - `THIRD_PARTY_MIRROR`: `hf-mirror.com`, `ghproxy.net`, `gh-proxy.com`.
  - `UNKNOWN`: Các host chưa xác thực khác.
  - `FORBIDDEN`: Các domain thuộc danh sách đen.
- **Chính sách Mirror bên thứ ba (Third-party Mirror Policy)**:
  - Các mirror thuộc nhóm `THIRD_PARTY_MIRROR` chỉ được tự động kích hoạt khi model có `expected_sha256` đi kèm để đối soát. Nếu không có SHA256, script sẽ tự động bỏ qua mirror này để bảo đảm tính toàn vẹn.

### 2.3 SHA256 Checksum
- **`validate_sha256(sha)`**:
  - Chấp nhận để trống (đối với model chưa có hash).
  - Nếu có giá trị: phải đúng 64 ký tự hex (`^[a-f0-9]{64}$`), không phân biệt hoa thường, tự động chuẩn hóa về chữ thường.
  - Từ chối tiền tố `sha256:`, khoảng trắng bên trong, hoặc chuỗi không đủ/quá 64 ký tự.

### 2.4 Cấu Hình Số (Numeric Configurations)
- **`validate_numeric_config(name, value, min, max)`**:
  - Bắt buộc là số nguyên dương trong giới hạn an toàn:
    - `MAX_RETRIES`: `1..20`
    - `TIMEOUT`: `5..3600` (giây)
    - `REQUIRED_SPACE_GB`: `0..100000` (GB)
    - `ARIA2_CONNECTIONS_MAX`: `1..16`
  - Chặn đứng mọi chuỗi chứa shell payload (ví dụ `5; rm -rf /`).

### 2.5 User-Agent & API Token
- **`validate_user_agent(ua)`**: Không được rỗng, không chứa ký tự xuống dòng hoặc NUL injection.
- **`validate_token_input(token)`**: Tự động dọn dẹp các tiền tố vô tình copy (`token=`, `?token=`), từ chối ký tự điều khiển, không bao giờ log giá trị thô.

---

## 3. Các Mã Lỗi Chuẩn Hóa (Structured Error Codes)

| Mã Lỗi | Ý Nghĩa |
|---|---|
| `E_PATH_EMPTY` | Đường dẫn bị rỗng |
| `E_PATH_UNSAFE_ROOT` | Đường dẫn trỏ vào root hệ thống hoặc thư mục nhạy cảm |
| `E_PATH_OUTSIDE_MODELS` | Model destination nằm ngoài thư mục `$MODELS` |
| `E_PATH_OUTSIDE_NODES` | Node destination nằm ngoài thư mục `$CUSTOM_NODES` |
| `E_PATH_TRAVERSAL` | Phát hiện kỹ thuật duyệt đường dẫn trái phép (`..`) |
| `E_CONTROL_CHAR_INJECTION` | Phát hiện ký tự điều khiển, xuống dòng hoặc ký tự shell |
| `E_INVALID_URL` | URL không thể parse hoặc định dạng sai |
| `E_INVALID_URL_SCHEME` | Giao thức không phải HTTP/HTTPS |
| `E_FORBIDDEN_DOMAIN` | Domain nằm trong danh sách cấm (`civitai.red`) |
| `E_SHA256_FORMAT` | Định dạng SHA256 không đúng 64 hex |
| `E_DUPLICATE_MODEL_KEY` | Trùng lặp đường dẫn đích trong file cấu hình model |
| `E_DUPLICATE_NODE_KEY` | Trùng lặp đường dẫn đích trong file cấu hình node |
| `E_BACKUP_KEY_MISMATCH` | Tập key giữa `models_list.csv` và `models_backup_list.csv` không khớp tuyệt đối |
| `E_INVALID_NUMERIC_CONFIG` | Cấu hình số không hợp lệ |
| `E_NUMERIC_OUT_OF_BOUNDS` | Giá trị cấu hình vượt ngoài khoảng an toàn |
| `E_INVALID_USER_AGENT` | User-Agent không hợp lệ |
| `E_INVALID_TOKEN_INPUT` | Token chứa ký tự không hợp lệ |
| `E_CONFIG_TOO_LARGE` | File cấu hình vượt quá dung lượng tối đa 5MB |
| `E_CONFIG_LINE_TOO_LONG` | Dòng cấu hình vượt quá 16KB |
| `E_NO_DOWNLOADER` | Hệ thống thiếu toàn bộ công cụ tải (curl, wget, aria2, python3) |

---

## 4. Chế Độ Kiểm Tra Read-Only (`--validate`)

Người dùng hoặc hệ thống CI/CD có thể chạy kiểm tra toàn diện mà **không làm thay đổi bất kỳ file nào trên hệ thống**:

```bash
# Kiểm tra toàn bộ cấu hình hệ thống, model và nodes
./install.sh --validate

# Chỉ kiểm tra cấu hình models
./install_models.sh --validate

# Chỉ kiểm tra cấu hình custom nodes
./install_nodes.sh --validate
```

- **Mã thoát (Exit Code)**:
  - `0`: Toàn bộ kiểm tra đạt yêu cầu (`PASS`).
  - `1`: Phát hiện lỗi cấu hình (`BLOCKED`).
