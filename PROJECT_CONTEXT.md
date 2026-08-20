# PROJECT_CONTEXT.md — ComfyUI Setup Automated Pipeline

## 1. Mục Tiêu Dự Án
Bộ script Bash & Python mô-đun hóa, hoàn toàn tự động cài đặt, tối ưu hóa đĩa cứng, và khôi phục lỗi cho **ComfyUI** trên các nền tảng Linux Server / Cloud GPU (Google Colab, RunPod, Vast.ai, Kaggle, SageMaker, Local Linux).

## 2. Kiến Trúc Cốt Lõi & Giai Đoạn Thực Thi
```text
install.sh (Entry point)
  ├── scripts/validation.sh       ← Input validation & Preflight Safety Gate
  ├── scripts/common.sh           ← Core shared library, multi-downloader & integrity
  ├── scripts/01_env_setup.sh     ← Stage 01: System packages & PyTorch runtime
  ├── scripts/02_comfy_core.sh    ← Stage 02: ComfyUI core clone & token handling
  ├── scripts/03_nodes_setup.sh   ← Stage 03: Custom nodes clone & dependency resolution
  ├── scripts/04_models_dl.sh     ← Stage 04: Multi-mirror download & state machine
  ├── scripts/05_manifest.sh      ← Stage 05: Markdown & JSON report generation
  └── scripts/06_gdrive_sync.sh   ← Stage 06: Output images sync to Google Drive
```

## 3. Các Invariants Bắt Buộc Của Dự Án
1. **Key đối soát CSV**: Key đối soát giữa `config/models_list.csv` và `config/models_backup_list.csv` là đường dẫn chính xác `$MODELS/...` (Exact set equality).
2. **Forbidden Domain**: Tuyệt đối cấm domain `civitai.red` và mọi subdomain `*.civitai.red`.
3. **Format Progress**: Giữ nguyên định dạng `⬇️  [X/Y] Tải: ...` cho parser bên ngoài.
4. **User-Agent**: Mọi request HTTP đều phải dùng Chrome-like `USER_AGENT`.
5. **Resume & Integrity**: Hỗ trợ Range resume với `.part.meta.json` sidecar, chống ô nhiễm chéo file `.part`, kiểm tra kích thước header + tensor offsets của file `safetensors`.
6. **Zero-Secret Serialization**: Token Civitai tuyệt đối không được ghi ra log, state JSON hay stdout/stderr.
7. **Canonical Containment**: Mọi đường dẫn model/node đều được kiểm tra containment (chống symlink escape và path traversal).
8. **Third-Party Mirror Policy**: Các mirror bên thứ ba tự động chỉ được tải khi có SHA256 đi kèm.

## 4. Trạng Thái Release
- **Git Commit**: `62f1f6b` — `harden installer validation and download recovery`
- **Remote**: `git@github.com:hung187/comfyui-setup1.git` (branch `main`)
- **Regression Tests**: 9/9 Groups PASS, 26/26 Scenarios PASS, 81/81 Assertions PASS.
- **Preflight Mode**: `./install.sh --validate` (Read-only, zero filesystem mutations).
