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
- **Remote**: `git@github.com:hung187/comfyui-setup1.git` (branch `main`)
- **HEAD Commit**: `4967ca5c132277685180d6b4e4b47b1f6e12af8f` (`fix: install ComfyUI Core requirements during stage 02`)
- **Remote CI**: GitHub Actions Quality Gate — **PASS (100% Success)**
- **Regression Tests**: 11/11 Groups PASS, 39/39 Scenarios PASS, 113/113 Assertions PASS.
- **Live GPU Test (EzyCloud RTX 3070 8GB)**:
  - `install_nodes.sh`: Clean installation, 0 tunnels opened, 0 auto-reload.
  - `install_models.sh`: 20 downloads OK / 19 verified models on disk (46.8 GB), 27 Civitai-token-gated models failed gracefully with full logging.
  - Production resume: Verified working.
  - ComfyUI startup: Started on CUDA:0 with 8049 MB free VRAM.
  - Workflow execution: SDXL Juggernaut Ragnarok test prompt generated successfully in 11.60s.
  - Verdict: `PARTIAL — GPU VRAM insufficient for SDXL/TRELLIS acceptance` (8 GB < 16 GB required for TRELLIS.2).

