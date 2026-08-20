# 🌟 BASELINE V1 RELEASE REPORT: `comfyui-setup1`

> **Document Version**: `v1.0-Final-Release-Baseline`
> **Evaluation Date**: `2026-08-20`
> **Final Verdict**: `PASS WITH WARNINGS` (Token rotation recommendation due to historical commit)

---

## 1. FUNCTIONAL ACCEPTANCE STATUS

- **Stage Execution Order**:
  `install.sh` ➔ `01_env_setup.sh` ➔ `02_comfy_core.sh` ➔ `03_nodes_setup.sh` ➔ `04_models_dl.sh` ➔ `05_manifest.sh` ➔ `06_gdrive_sync.sh`.
- **Invariants Preserved**:
  - `KEYS(backup) == KEYS(primary)` in `config/models_list.csv` and `config/models_backup_list.csv`.
  - `civitai.red` is strictly forbidden across all mirrors and dynamic fallbacks.
  - Parser-dependent progress log format `⬇️  [X/Y] Tải: ...` remains intact.
  - All download engines use Chrome-like `USER_AGENT`.
  - Resume uses temporary `.part` files with atomic move to `$output_path`.

---

## 2. SECURITY FINDINGS SUMMARY

| ID | SEVERITY | DESCRIPTION | STATUS |
|:---:|:---:|:---|:---:|
| **F-01** | **HIGH** | Safetensors header validation bypassed on `.part` files | ✅ **RESOLVED** |
| **F-02** | **HIGH** | Concurrency race conditions & lost updates in JSON state files | ✅ **RESOLVED** |
| **F-03** | **MEDIUM** | Plaintext tokens in log files and state JSON files | ✅ **RESOLVED** |
| **F-04** | **MEDIUM** | Non-strict subset check and path traversal in mirror validator | ✅ **RESOLVED** |
| **F-05** | **LOW** | Blind `pip install` on unknown AST imports in `fix_nodes.sh` | ✅ **RESOLVED** |
| **F-06** | **LOW** | Hardcoded `python3`/`pip3` instead of active virtualenv | ✅ **RESOLVED** |

---

## 3. SECRET HISTORY AUDIT

```text
SECRET_HISTORY_STATUS:
- Working tree: CLEAN
- Git history: FOUND (Historical commit c1c911b created prior to this session contained an unmasked token in comfyui_colab.ipynb)
- Old archives: FOUND (comfyui-setup1-review.tar.gz and comfyui-setup1-review-v2.tar.gz contained legacy .env.example)
- Final Baseline Archive (comfyui-setup1-baseline-v1.tar.gz): CLEAN
```

---

## 4. TOKEN ROTATION RECOMMENDATION

> [!WARNING]
> **TOKEN ROTATION RECOMMENDED**
> An unmasked Civitai token was found in the initial Git commit history (`c1c911b`). As per agent safety guidelines, the agent **will NOT automatically rewrite Git history or force-push**.
> **Recommendation for User**:
> 1. Rotate your API token at [Civitai Account Settings](https://civitai.com/user/account).
> 2. If desired, clean Git history locally using `git filter-repo` or BFG Repo-Cleaner before publishing repository publicly.

---

## 5. INTEGRITY GUARANTEES

1. **Safetensors 8-Byte Uint64 Header Validation**:
   - Strictly reads first 8 bytes (little endian) as header length $L$.
   - Enforces $8 + L \le \text{file\_size}$.
   - Parses the JSON metadata UTF-8 header via `json.loads()`.
   - Rejects HTML, Cloudflare error pages, XML payloads, and random binary files.
2. **PyTorch Magic Byte Check**:
   - Validates Zip header (`PK\x03\x04`) or pickle magic bytes (`\x80\x02` .. `\x80\x05`).
3. **Atomic File Commitment**:
   - Downloads stream to `${output_path}.part`.
   - Verification runs directly on the `.part` file.
   - Only moves `.part` to `$output_path` after verification passes.
   - Deletes corrupt `.part` files immediately on verification failure.

---

## 6. MULTI-MIRROR RECOVERY MATRIX

```
[Candidate URL]
   │
   ├─► check_url_alive (HEAD request)
   │     ├─► 200/206/301/302/307 ──► PROCEED TO DOWNLOAD
   │     ├─► 404/410 ──────────────► Mark DEAD in source_health.json ──► NEXT CANDIDATE
   │     └─► 429 ──────────────────► Degrade health score ───────────► NEXT CANDIDATE
   │
   ├─► exec_download_tool (aria2c ──► wget ──► curl ──► urllib)
   │     └─► Downloads stream to: ${output_path}.part
   │
   ├─► verify_model_file (${output_path}.part, expected_sha256)
   │     ├─► Valid Safetensors / PyTorch format
   │     └─► Optional SHA256 match
   │
   ├─► Verification FAILS ─────────► rm -f ${output_path}.part ──► NEXT CANDIDATE
   └─► Verification PASSES ────────► mv ${output_path}.part $output_path ──► STATUS: COMPLETED
```

---

## 7. PERFORMANCE BENCHMARK RESULTS

- **Test Source**: HuggingFace AWS CloudFront CDN (`distilbert-base-uncased/model.safetensors`, 267.95 MB).
- **Results**:
  - `wget` (single-stream): **15.47 – 30.66 MB/s** (Avg: 23.07 MB/s)
  - `curl` (single-stream): **24.13 – 30.49 MB/s** (Avg: 27.31 MB/s)
  - `python3 urllib` (single-stream): **14.13 – 28.49 MB/s** (Avg: 21.31 MB/s)
- **Range Resume (Internet Test)**:
  - Downloaded initial 50 MB slice.
  - Interrupted and resumed via `curl -C -` in 8.12s.
  - Final file size: 267,954,768 bytes (100% exact match).
  - SHA256 validated: `5e3f1108e3cb34ee048634875d8482665b65ac713291a7e32396fb18f6ff0063`.

---

## 8. RECOMMENDED DOWNLOADER POLICY

- **Default Connections**: 4–8 connections per model file.
- **Adaptive Throttling**:
  - On HTTP 429: Connection count automatically throttled to 2 connections with exponential backoff.
  - First-party sources (`huggingface.co`, `civitai.com`): 8 connections.
  - GitHub sources (`github.com`): 4 connections.
- **Override Support**: `ARIA2_CONNECTIONS_MAX` (clamps between 1 and 16).

---

## 9. GLOBAL CONCURRENCY POLICY

- **Linear Model Downloads**: Model downloads process sequentially (`MAX_PARALLEL_MODELS=1` by default) to prevent network congestion, file descriptor starvation, and multi-file rate limits on Cloud GPU instances.
- **Flock Protected State Files**: Concurrent writes to `source_health.json` and `download_state.json` use POSIX `fcntl.flock` on `.lock` files, PID/nanosecond unique temp files, and `os.fsync`.

---

## 10. KNOWN LIMITATIONS

1. **Civitai Gated / NSFW Models**: If user API token lacks NSFW permissions on `civitai.com/user/account`, Civitai returns an HTML login redirect. The engine rejects the file and falls back to HuggingFace mirrors.
2. **System C++ Libraries for Nodes**: `fix_nodes.sh` handles Python dependencies. System packages (C++ build tools, OpenGL, CUDA drivers) require pre-installed host packages.

---

## 11. TEST TOTALS

```text
TEST GROUPS         : 8 / 8 PASS (100%)
INDIVIDUAL SCENARIOS : 21 / 21 PASS (100%)
ASSERTIONS RUN       : 25 / 25 PASS (100%)
SYNTAX AUDIT        : 100% PASS across all .sh scripts
```

---

## 12. REAL NETWORK EVIDENCE

- Live DNS, TLS handshake, HTTP 302 redirect follow, and User-Agent headers verified against HuggingFace CDN.
- Real Range resume tested and validated byte-for-byte on a live 268MB model.

---

## 13. REMAINING WARNINGS

- `UNSAFE OLD ARCHIVES`: `comfyui-setup1-review.tar.gz` and `comfyui-setup1-review-v2.tar.gz` contained historical token references. These are excluded from the baseline release.
- `USER ACTION REQUIRED`: Token rotation recommended due to historical Git commit.

---

## 14. FINAL VERDICT

### 🏆 `PASS WITH WARNINGS`

*(Production-ready baseline with zero functional/security defects; user token rotation recommended).*
