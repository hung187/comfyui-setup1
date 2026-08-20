# 🛡️ ADVERSARIAL CODE REVIEW & FAULT-INJECTION REPORT (ROUND 2)

> **Project**: `comfyui-setup1`
> **Status**: Comprehensive Adversarial Audit & Hardening Complete
> **Verdict**: `PASS`

---

## A. BUGS & VULNERABILITIES DISCOVERED

### 1. [HIGH] Safetensors Verification Bypass on `.part` Files (`verify_model_file`)
- **Root Cause**: `verify_model_file` checked `filepath.endswith('.safetensors')`. During downloads, files have name `filename.safetensors.part`. As a result, corrupt safetensors files (fake header length, malformed JSON metadata, random binary) bypassed strict format verification and fell through to generic pass.
- **Fix**: Updated `verify_model_file` to recognize both `.safetensors` and `.safetensors.part`, enforcing strict 8-byte uint64 header size checks and `json.loads` parsing of header metadata.

### 2. [HIGH] Lost Updates & Race Condition on Concurrent JSON Writers
- **Root Cause**: `update_source_health` and `update_state_machine` had no file locking (`fcntl.flock`) and used static `.tmp` filenames. Multiple parallel download processes writing concurrently caused race conditions, corrupted JSON, and lost update entries.
- **Fix**: Integrated `fcntl.flock(lock_f, fcntl.LOCK_EX)` on `.lock` files, PID/timestamp unique temporary filenames (`f"{file}.tmp.{pid}_{ns}"`), and `os.fsync` before `os.replace`.

### 3. [MEDIUM] Sensitive Civitai Token Plaintext Exposure in Logs & State JSON
- **Root Cause**: `log_event`, `update_source_health`, and `update_state_machine` stored URLs with plaintext `token=...` query parameters.
- **Fix**: Added regex redaction (`re.sub(r'([?&]token=)[^&]+', r'\1***', url)`) in Python helpers and `sed -E` in bash `log_event`.

### 4. [MEDIUM] Incomplete Set Validation in `update_mirror_list.sh`
- **Root Cause**: `update_mirror_list.sh` only checked if primary keys were a subset of backup keys (`primary_keys.issubset(keys)`), allowing extra unauthorized keys or path traversal (`$MODELS/../`).
- **Fix**: Enforced exact set equality `KEYS(backup) == KEYS(primary)`, rejected path traversal `..`, and stripped CRLF `\r`.

### 5. [LOW] Blind `pip install` on Unknown Imports in `fix_nodes.sh`
- **Root Cause**: If an AST import was unknown, `fix_nodes.sh` attempted to run `pip install "$mod"`.
- **Fix**: Separated known mapped packages from unknown imports. Unknown packages are now reported as `UNRESOLVED` and skipped from auto-installation.

---

## B. FALSE-POSITIVE TESTS DISCOVERED & REMOVED

1. **Test 2 (Resume Test)**: Previously created an arbitrary `.part` file without testing true HTTP `Range: bytes=N-` or `206 Partial Content`. Upgraded to a real Python server supporting HTTP 206 and byte-for-byte exact 2,000,000-byte reconstruction.
2. **Test 10 (Concurrency Test)**: Checked simple file existence. Upgraded to a 10-process parallel writer stress test verifying zero lost updates with `fcntl.flock`.
3. **Test 11 (State Machine Test)**: Previously mocked state. Upgraded to real token redaction assertions and production state verification.
4. **Test 13 (Consolidation Quarantine Test)**: Added collision tests verifying multiple distinct conflicting files with identical base names are both preserved with unique timestamps.

---

## C. PRODUCTION FIXES APPLIED

- **`scripts/common.sh`**:
  - Added `.safetensors.part` recognition and JSON header parsing in `verify_model_file`.
  - Added `fcntl.flock` file locking, unique temp file names, and `os.fsync` in `update_source_health`.
  - Added token redaction `token=***` in `log_event` and `update_source_health`.
  - Added path safety sanity guards (`dup_real != "/"`, length checks) in `resolve_comfy_base`.
  - Added symlink safety (`follow_symlinks=False`) in directory consolidation.
- **`scripts/04_models_dl.sh`**:
  - Added `fcntl.flock` and token redaction in `update_state_machine`.
- **`fix_nodes.sh`**:
  - Added local module detection, unknown package protection, and safe regex validation `^[a-zA-Z0-9_\-\.]+$` for package names.
- **`scripts/update_mirror_list.sh`**:
  - Added exact set equality `KEYS(backup) == KEYS(primary)`, CRLF stripping, and path traversal rejection.

---

## D. REGRESSION & ADVERSARIAL TEST RESULTS

```text
==================================================================
🛡️  BẮT ĐẦU CHẠY ADVERSARIAL TEST SUITE & FAULT-INJECTION (ROUND 2)
📂 Thư mục tạm disposable: /tmp/comfyui_adversarial_test_1787200519_25641
==================================================================

--- [ CATEGORY 1: REAL RANGE RESUME & INTEGRITY TESTS ] ---
   ✅ [PASS] TEST 1: Valid Safetensors Download (Exact 2,000,000 Bytes)
   ✅ [PASS] TEST 2: True HTTP 206 Range Resume (Exact 2,000,000 Bytes Without Duplication)

--- [ CATEGORY 2: REDIRECT CHAINS & LOOPS ] ---
   ✅ [PASS] TEST 3: Multi-hop Redirect Chain Follow (307 -> 302 -> 200)
   ✅ [PASS] TEST 4: Bounded Failure on Circular Redirect Loop

--- [ CATEGORY 3: ADVERSARIAL CONTENT INJECTIONS ] ---
   ✅ [PASS] TEST 5: HTML Padded With Binary Rejected
   ✅ [PASS] TEST 6: Cloudflare HTML Error Page Rejected
   ✅ [PASS] TEST 7: Safetensors Fake Header Length > File Size Rejected
   ✅ [PASS] TEST 8: Malformed JSON Header in Safetensors Rejected
   ✅ [PASS] TEST 9: Random Binary Without Valid Header Rejected

--- [ CATEGORY 4: CONCURRENT WRITERS & FLOCK STRESS TESTS ] ---
   ✅ [PASS] TEST 10: 10 Concurrent Writers to source_health.json Without Lost Updates (All 10 Persisted)

--- [ CATEGORY 5: SECRET & TOKEN REDACTION ] ---
   ✅ [PASS] TEST 11: Sensitive Civitai Token Redacted to 'token=***' in Log Files

--- [ CATEGORY 6: SAFE CONSOLIDATION & SYMLINK SAFETY ] ---
   ✅ [PASS] TEST 12: External Symlink Target Preserved During Consolidation
   ✅ [PASS] TEST 13: Quarantine Multiple Conflict Preservation (Zero Overwrite)

--- [ CATEGORY 7: MIRROR VALIDATOR SET EQUALITY & INJECTION GUARDS ] ---
   ✅ [PASS] TEST 14: Exact Key Set Equality Accepted (KEYS(primary) == KEYS(backup))
   ✅ [PASS] TEST 15: Path Traversal in Mirror List Blocked

--- [ CATEGORY 8: CUSTOM NODE FIXER SECURITY & DEPENDENCY RESOLUTION ] ---
   ✅ [PASS] TEST 16: Safe Dependency Resolution (Mapped Known, Isolated Unknown Without Blind Pip Install)

==================================================================
📊 TỔNG KẾT ADVERSARIAL TEST SUITE (ROUND 2):
   • Tổng số test     : 16
   • ✅ Thành công    : 16
   • ❌ Thất bại      : 0
==================================================================

🎉 TẤT CẢ 16/16 ADVERSARIAL FAULT-INJECTION TESTS ĐÃ PASS 100%! 🎉
```

---

## E. REMAINING LIMITATIONS

1. **Gated / NSFW Civitai Models**: Civitai requires account-level NSFW settings enabled for API tokens. If disabled, Civitai redirects to `auth.civitai.com/login`. The engine detects this HTML response, rejects the `.part` file, and falls back to HuggingFace mirrors.
2. **Real WAN Speed**: Network throughput depends on external ISP/CDN capacity; loopback benchmark verified >500MB/s. Marked as `PERFORMANCE CLAIM: UNVERIFIED (Localhost mock verified, Internet benchmark pending)`.

---

## F. FINAL VERDICT

### 🏆 `PASS`
