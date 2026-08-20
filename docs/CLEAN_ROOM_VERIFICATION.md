# Clean-Room Verification & CI Reproducibility Report

Báo cáo kiểm chứng độc lập mã nguồn trên môi trường sạch (**Clean-Room Environment**) sau khi triển khai lên kho lưu trữ GitHub chính thức.

---

## 1. Thông Tin Môi Trường & Remote Kiểm Thử

- **Remote Tested**: `git@github.com:hung187/comfyui-setup1.git` (https://github.com/hung187/comfyui-setup1)
- **Branch**: `main`
- **Initial Clean Clone HEAD**: `cb255fa6796414d933f5b9aaf9e49ab2ec01a0c6`
- **Environment**: Linux x86_64, Disposable Temporary Namespace (`/tmp/comfyui_remote_verify.*`)
- **Isolation Guarantee**: Không kế thừa biến môi trường, cache, hay file uncommitted nào từ workspace phát triển cục bộ.

---

## 2. Kết Quả Kiểm Chứng Từng Hạng Mục

| Hạng Mục Kiểm Tra | Kết Quả | Chi Tiết |
|---|---|---|
| **Hidden / Untracked Dependencies** | `NONE (PASS)` | 100% các file runtime, modules, configs và docs đều được track đầy đủ trong Git. |
| **Bash Syntax Check (`bash -n`)** | `PASS` | Kiểm tra cú pháp toàn bộ scripts (`install.sh`, `install_models.sh`, `install_nodes.sh`, `fix_nodes.sh`, `reload.sh`, `scripts/*.sh`, `tests/*.sh`). |
| **Production Test Suite** | `PASS (9/9 Groups)` | Chạy trực tiếp `bash tests/run_tests.sh`: 26 Scenarios, 81 Assertions đạt 100%. |
| **Validate-Only Preflight Mode** | `PASS` | `./install.sh --validate`, `./install_models.sh --validate`, `./install_nodes.sh --validate` chạy sạch, không gây đột biến file hệ thống. |
| **Fresh Dry-Run Mode** | `PASS` | Kiểm thử `bash install.sh --dry-run` với thư mục `COMFY_BASE` hoàn toàn mới: State machine, pipeline stages, và parser xử lý trơn tru 42/42 models. |
| **Source Import Safety** | `PASS` | Sourcing các module (`common.sh`, `validation.sh`, `04_models_dl.sh`, `fix_nodes.sh`, `update_mirror_list.sh`) trong subshell độc lập chỉ định nghĩa hàm, không tạo ra bất kỳ tác dụng phụ hay file rác nào. |
| **Error Propagation Gate** | `PASS` | Các cấu hình lỗi (`MAX_RETRIES` ngoài ngưỡng, CSV hỏng, v.v.) được phát hiện và trả mã thoát non-zero đồng bộ trên mọi entrypoint. |
| **Network Smoke Test** | `PASS` | Tải thử nghiệm artifact thật từ GitHub qua HTTPS/TLS, áp dụng User-Agent Chrome-like và kiểm tra đối soát SHA256 thành công. |
| **Current HEAD Secret Scan** | `PASS (CLEAN)` | Cây thư mục hiện tại của HEAD không chứa bất kỳ API token, mật khẩu, cookies, hay private key nào. |

---

## 3. Thống Kê Cấu Hình & Phân Loại Độ Tin Cậy Nguồn (Source Trust)

- **Tổng số Models chính thức**: `42`
- **Tổng số Backup Mirror entries**: `42` (Khớp tập key 100% với `models_list.csv`)
- **Tổng số Custom Nodes**: `14` (Toàn bộ dùng giao thức HTTPS)
- **Số Models có SHA256**: `0` (Đang sử dụng kiểm tra toàn vẹn cấu trúc Safetensors Tensor Offset)
- **Số Models chưa có SHA256**: `42`
- **Phân loại nguồn URL**:
  - `OFFICIAL_FIRST_PARTY`: `127` (Civitai, HuggingFace, GitHub)
  - `THIRD_PARTY_MIRROR`: `16` (hf-mirror.com)
  - `UNKNOWN`: `0`
  - `FORBIDDEN`: `0` (Tuyệt đối không chứa `civitai.red`)

---

## 4. Cảnh Báo Bảo Mật Lịch Sử (Historical Secret Notice)

- **Phát hiện**: Một token Civitai chưa được mask từng xuất hiện trong commit lịch sử ban đầu (`c1c911b`).
- **Khuyến nghị**: Người dùng nên chủ động Rotate / Thu hồi token cũ trên Civitai và tạo token mới.
- **Chính sách**: Không tự ý rewrite Git history hoặc force push để bảo vệ tính toàn vẹn của nhánh chính.

---

## 5. Thiết Lập CI Quality Gate

Workflow tự động hóa đã được thiết lập tại `.github/workflows/quality-gate.yml` nhằm bảo vệ chất lượng mã nguồn trên mỗi lượt `push` và `pull_request` vào nhánh `main`.
