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

## 4. Automatic 3D Output Google Drive Sync
- **Module**: `scripts/06_gdrive_sync.sh`
- **Output Whitelist**: `.glb`, `.gltf`, `.obj`, `.mtl`, `.png`, `.jpg`, `.jpeg`, `.webp`, `.json` inside `$COMFY_BASE/output` (recursive).
- **Prohibited Blacklist**: `models/`, `custom_nodes/`, `.cache/`, `.part`, `.tmp`, `.lock`, `.pid`, `.log`, `.meta.json`, `*download_state*`, `*setup_report*`, `*source_health*`, secrets, dotfiles.
- **Process & Lifecycle Guard**: Single watcher daemon per ComfyUI instance protected by exclusive `flock` (`$COMFY_BASE/.gdrive_3d_watcher.lock`) and tracked via `$COMFY_BASE/.gdrive_3d_watcher.pid`. Graceful stop targeting daemon PID (`SIGTERM` -> `SIGKILL` timeout escalation), zero `pkill -f` collateral damage.
- **Atomic Remote Staging Protocol**: Staged upload to `gdrive:ComfyUI_3D_Output/<relpath>.partial` via `rclone copyto` -> size/integrity verification -> atomic remote rename via `rclone moveto`.
- **Zero Local Data Loss**: Network/rclone failures retain 100% of original local files with exponential backoff retries.
- **Security & Perms**: `rclone.conf` strictly guarded with permissions `600`, parent directory `700`. Zero credential leaks.
- **CLI Commands**:
  - Start/Install: `bash install_nodes.sh --gdrive-3d --gdrive-folder ComfyUI_3D_Output` (or `bash install.sh --gdrive-3d`)
  - Stop: `bash install_nodes.sh --stop-gdrive-3d` (or `bash install.sh --stop-gdrive-3d` / `bash scripts/06_gdrive_sync.sh --stop-watcher`)
  - Status: `bash install_nodes.sh --status-gdrive-3d` (or `bash install.sh --status-gdrive-3d`)

## 5. Trạng Thái Test Suite & Nghiệm Thu Thực Tế (Real GPU Acceptance)
- **Unit & Integration Tests**: **12 / 12 Groups PASS**, **51 / 51 Scenarios PASS**, **181 / 181 Assertions PASS (100% Success)**.
- **Group 12 Coverage**:
  - `12.1` - `12.7`: 3D Output Whitelist, Blacklist, Atomic Staging, Flock Guard, Safe Failure (PASS).
  - `12.8` - `12.12`: Non-secret Marker Lifecycle, Installer Auto-Start, Dedup State, Zero-Persistence (PASS).
- **Real Cloud GPU Acceptance Test (Tesla V100 16GB)**:
  - Hardware: Tesla V100-PCIE-16GB (16,384 MiB VRAM), 200 GB Storage Overlay.
  - Two-Stage Execution: Stage 1 (`install_nodes.sh`) + Pod Restart + Stage 2 (`install_models.sh`).
  - Custom Nodes: 12/12 Installed & Verified OK.

## 6. NEXUS SENTINEL — 100 2D Celestial Source Images (ComfyUI API Batch)
- **Engine**: ComfyUI API (`127.0.0.1:8188`) via `/prompt` and `/history/{id}`.
- **Model**: `SDXL/juggernautXL_ragnarok.safetensors` (1024x1024, Steps: 30, CFG: 7.0, Sampler: `dpmpp_2m`, Scheduler: `karras`, Denoise: 1.0).
- **Execution Policy**: Strict 1-by-1 sequential queue, 0 concurrent jobs, automatic resume capability via stateful manifest.
- **Output Directory**: `/app/ComfyUI/output/nexus_sentinel/celestial_source_100/`
- **Manifest**: `/app/ComfyUI/output/nexus_sentinel/celestial_source_100/manifest.json`
- **Script**: `/root/nexus_batch_generator.py` (Local: `/home/kurogame/comfyui-setup1/nexus_batch_generator.py`)
- **Structure Breakdown (100/100 COMPLETED, 0 FAILURES)**:
  - 42 Normal Planets (`normal_planet` / `mesh_candidate`): `celestial_001` - `celestial_042` (42/42 OK)
  - 15 Ringed Planets (`ringed_planet` / `mesh_candidate`): `celestial_043` - `celestial_057` (15/15 OK)
  - 8 Black Holes (`black_hole` / `effect_candidate`): `celestial_058` - `celestial_065` (8/8 OK)
  - 7 White Holes (`white_hole` / `effect_candidate`): `celestial_066` - `celestial_072` (7/7 OK)
  - 8 Neutron Stars / Pulsars (`neutron_star_pulsar` / `mesh_candidate`): `celestial_073` - `celestial_080` (8/8 OK)
  - 10 Host Stars (`host_star` / `mesh_candidate`): `celestial_081` - `celestial_090` (10/10 OK)
  - 5 Galaxies / Superclusters (`galaxy_supercluster` / `background_only`): `celestial_091` - `celestial_095` (5/5 OK)
  - 5 Asteroid Belts / Dust (`asteroid_belt_dust` / `background_only`): `celestial_096` - `celestial_100` (5/5 OK)

## 7. NEXUS SENTINEL — Batch 2 (200 Generated → 100 Selected Celestial Source Images)
- **Engine**: ComfyUI API (`127.0.0.1:8188`), Checkpoint `SDXL/juggernautXL_ragnarok.safetensors`.
- **KSampler**: 1024x1024, Steps: 35, CFG: 7.0, Sampler: `dpmpp_2m`, Scheduler: `karras`, Denoise: 1.0, fixed seed per item.
- **Batch 200 Full Generation**: 200 / 200 COMPLETED (0 failures) at `/app/ComfyUI/output/nexus_sentinel/celestial_source_200/`.
- **Contact Sheets**: `contact_sheet_200.jpg` (1780x3880) and `contact_sheet_selected_100.jpg` (1780x1960).
- **Curated Selection (100 Selected)**: `/app/ComfyUI/output/nexus_sentinel/celestial_source_200_selected_100/`
  - 60 Normal Planets (`normal_planet`)
  - 15 Ringed Planets (`ringed_planet`)
  - 10 Black/White Holes (`black_hole`: 5, `white_hole`: 5)
  - 10 Host Stars / Pulsars (`host_star`: 5, `neutron_star_pulsar`: 5)
  - 5 Galaxies / Belts (`galaxy_supercluster`: 3, `asteroid_belt_dust`: 2)
- **ZIP Package**: `/app/ComfyUI/output/nexus_sentinel/nexus_sentinel_celestial_source_200_selected_100.zip` (125,049,731 bytes / 119.26 MB).
- **SHA-256**: `e28cb9af9cc9ee160871afa3271998fcd4267cce9bb8be0a262b0f2d656cf6ef`.

## 8. Real Cloud GPU Deployment & Acceptance (RTX 3090 24GB)
- **Host / IP**: `159.48.242.3:21406`
- **Hardware**: NVIDIA GeForce RTX 3090 (24,576 MiB VRAM), 200 GB Storage Overlay.
- **Base Environment**: Fresh minimal container with Python 3.10.12.
- **Runtime Setup**: Automated installation of PyTorch 2.6.0+cu124, `build-essential`, `python3-dev`, `ffmpeg`, `libgl1`, `aria2`, `jq`.
- **Custom Nodes**: 12/12 Custom Nodes (ComfyUI-Manager, TRELLIS2 3D, ControlNet Aux, IP-Adapter Plus, WAS Node Suite, KJNodes, rgthree, Inpaint, Easy Use, LayerStyle, Custom Scripts, Ultimate SD Upscale) imported cleanly in under 2 seconds with 0 failed nodes.
- **Models Downloaded**: 40 / 40 models (Illustrious XL & SDXL Checkpoints, TRELLIS2 3D models, ControlNet, IP-Adapter, VAEs, Upscalers, LoRAs) processed with 0 failures (100% success rate).
- **Active Service**: ComfyUI listening on `http://0.0.0.0:8188` (`--highvram`).
- **Render Acceptance**: Sample generation (`IL/oneObsession_v23.safetensors`, 512x512, seed 42) executed via API and verified file `ComfyUI_Acceptance_Test_00001_.png` generated in < 10 seconds.
