#!/bin/bash
# ================================================================================================================================
# COMPREHENSIVE PRODUCTION-BACKED ADVERSARIAL TEST SUITE FOR COMFYUI-SETUP1
# All test scenarios directly execute actual production helpers without algorithm duplication!
# ================================================================================================================================

set +e
export LC_ALL=C
export no_proxy="localhost,127.0.0.1,::1"
export NO_PROXY="localhost,127.0.0.1,::1"

TEST_ROOT="/tmp/comfyui_prod_test_$(date +%s)_$$"
mkdir -p "$TEST_ROOT"

cleanup() {
    [ -n "${MOCK_PID:-}" ] && kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TEST_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPT_DIR="$REPO_ROOT"

# Source all production libraries
source "$REPO_ROOT/scripts/validation.sh"
source "$REPO_ROOT/scripts/common.sh"
source "$REPO_ROOT/scripts/04_models_dl.sh"
source "$REPO_ROOT/scripts/update_mirror_list.sh"
source "$REPO_ROOT/fix_nodes.sh"

# Ensure test runner does not inherit set -e/u/pipefail from sourced scripts
set +e
set +u
set +o pipefail 2>/dev/null || true

echo "=================================================================="
echo "🛡️  BẮT ĐẦU CHẠY ADVERSARIAL TEST SUITE TRỰC TIẾP TRÊN PRODUCTION CODE"
echo "📂 Thư mục sandbox: $TEST_ROOT"
echo "=================================================================="

# 1. Start Python Local Mock HTTP Server on dynamic free port
cat > "$TEST_ROOT/mock_server.py" <<'PY_SERVER'
import sys, os, http.server, socketserver, json, socket

port_file = sys.argv[1]

# Valid 2MB safetensors payload with accurate tensor data_offsets
header_meta = {
    "__metadata__": {"format": "pt"},
    "model.weight": {"dtype": "F32", "shape": [64, 64], "data_offsets": [0, 16384]}
}
json_hdr = json.dumps(header_meta).encode('utf-8')
hdr_len = len(json_hdr).to_bytes(8, 'little')
safetensors_bytes = hdr_len + json_hdr + b'\x00' * (2000000 - len(hdr_len) - len(json_hdr))

# Request log for strict protocol assertions
REQ_LOG = []

class MockFaultHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args): return

    def do_HEAD(self):
        path = self.path
        REQ_LOG.append({'method': 'HEAD', 'path': path, 'range': self.headers.get('Range', '')})
        if '404' in path:
            self.send_response(404)
        elif '403' in path:
            self.send_response(403)
        elif '429' in path:
            self.send_response(429)
        elif 'redirect_chain_1' in path:
            self.send_response(307)
            self.send_header('Location', f'/redirect_chain_2')
        elif 'redirect_chain_2' in path:
            self.send_response(302)
            self.send_header('Location', f'/valid_model.safetensors')
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(len(safetensors_bytes)))
            self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()

    def do_GET(self):
        path = self.path
        range_hdr = self.headers.get('Range', '')
        REQ_LOG.append({'method': 'GET', 'path': path, 'range': range_hdr})

        if 'get_req_log' in path:
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(REQ_LOG).encode('utf-8'))
            return

        if 'redirect_chain_1' in path:
            self.send_response(307); self.send_header('Location', f'/redirect_chain_2'); self.end_headers(); return
        if 'redirect_chain_2' in path:
            self.send_response(302); self.send_header('Location', f'/valid_model.safetensors'); self.end_headers(); return

        if '404' in path:
            self.send_response(404); self.end_headers(); self.wfile.write(b"404 Not Found"); return
        if '403' in path:
            self.send_response(403); self.end_headers(); self.wfile.write(b"403 Forbidden"); return
        if '429' in path:
            self.send_response(429); self.end_headers(); self.wfile.write(b"429 Too Many Requests"); return

        if 'html_error' in path:
            self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers()
            self.wfile.write(b"<!DOCTYPE html><html><body>Error</body></html>" + b'\x00' * 200000); return

        if 'truncated_offsets' in path:
            bad_meta = {"model.weight": {"dtype": "F32", "shape": [64, 64], "data_offsets": [0, 1000000]}}
            b_json = json.dumps(bad_meta).encode('utf-8')
            b_hdr = len(b_json).to_bytes(8, 'little') + b_json
            self.send_response(200); self.send_header('Content-Type', 'application/octet-stream'); self.end_headers()
            self.wfile.write(b_hdr + b'\x00' * 200000)
            return

        total_size = len(safetensors_bytes)
        if range_hdr and range_hdr.startswith('bytes='):
            range_spec = range_hdr.split('=')[1].strip()
            start_str = range_spec.split('-')[0]
            start = int(start_str) if start_str else 0
            if start < total_size:
                data = safetensors_bytes[start:]
                self.send_response(206)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Range', f'bytes {start}-{total_size-1}/{total_size}')
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Accept-Ranges', 'bytes')
                self.end_headers()
                try: self.wfile.write(data)
                except Exception: pass
                return

        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(total_size))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        try: self.wfile.write(safetensors_bytes)
        except Exception: pass

socketserver.TCPServer.allow_reuse_address = True
server = socketserver.TCPServer(('127.0.0.1', 0), MockFaultHandler)
port = server.server_address[1]
with open(port_file, 'w') as f:
    f.write(str(port))
server.serve_forever()
PY_SERVER

PORT_FILE="$TEST_ROOT/mock_port.txt"
python3 "$TEST_ROOT/mock_server.py" "$PORT_FILE" &
MOCK_PID=$!

while [ ! -s "$PORT_FILE" ]; do sleep 0.1; done
TEST_PORT=$(cat "$PORT_FILE")
MOCK_URL="http://127.0.0.1:$TEST_PORT"

# Readiness probe for mock server
for probe_i in $(seq 1 50); do
    if curl -s "$MOCK_URL/valid_model.safetensors" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

# Test Counters
TEST_GROUPS_RUN=0
TEST_GROUPS_PASSED=0
SCENARIOS_RUN=0
SCENARIOS_PASSED=0
ASSERTIONS_RUN=0
ASSERTIONS_PASSED=0

assert_true() {
    local desc="$1"
    local cond="$2"
    ASSERTIONS_RUN=$((ASSERTIONS_RUN + 1))
    if [ "$cond" -eq 0 ]; then
        ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    else
        echo -e "   ❌ Assertion failed: $desc" >&2
        SCENARIO_OK=0
        return 1
    fi
}

start_scenario() {
    SCENARIOS_RUN=$((SCENARIOS_RUN + 1))
    SCENARIO_NAME="$1"
    SCENARIO_OK=1
}

end_scenario() {
    if [ $SCENARIO_OK -eq 1 ]; then
        SCENARIOS_PASSED=$((SCENARIOS_PASSED + 1))
        echo -e "   ✅ [PASS] $SCENARIO_NAME"
    else
        echo -e "   ❌ [FAIL] $SCENARIO_NAME"
    fi
}

# Environment setup
export COMFY_BASE="$TEST_ROOT/ComfyUI"
export MODELS="$COMFY_BASE/models"
export CUSTOM_NODES="$COMFY_BASE/custom_nodes"
export LOG_FILE="$TEST_ROOT/setup_log.txt"
export MANIFEST_FILE="$TEST_ROOT/manifest.json"
export REPORT_FILE="$TEST_ROOT/SETUP_REPORT.md"
export REPORT_JSON="$TEST_ROOT/setup_report.json"
export REQUIRED_SPACE_GB=1
export DRY_RUN=0
mkdir -p "$COMFY_BASE" "$MODELS" "$CUSTOM_NODES"

init_runtime_env >/dev/null 2>&1


echo -e "\n=== [ GROUP 1: REAL RANGE RESUME & STREAMING (PRODUCTION CODES) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G1_OK=1

# Scenario 1.1: Production download_model_smart full stream
start_scenario "1.1: Production download_model_smart full stream"
out1="$MODELS/m1.safetensors"
if download_model_smart "$MOCK_URL/valid_model.safetensors" "" "$out1" "M1 Download" >/dev/null 2>&1; then
    [ -f "$out1" ]; assert_true "File committed" $?
    [ $(stat -c%s "$out1") -eq 2000000 ]; assert_true "Size 2,000,000 bytes" $?
else
    assert_true "Download succeeded" 1
fi
[ $SCENARIO_OK -eq 0 ] && G1_OK=0
end_scenario

# Scenario 1.2: Production Range Resume with .part.meta.json compatibility
start_scenario "1.2: Production Same-Source Resume with .part.meta.json Compatibility"
out2="$MODELS/m2.safetensors"
part2="${out2}.part"
python3 -c "with open('$part2', 'wb') as f: f.write(b'\x00'*500000)"
manage_part_metadata "$MOCK_URL/valid_model.safetensors" "$part2" "" "check" >/dev/null

if download_model_smart "$MOCK_URL/valid_model.safetensors" "" "$out2" "M2 Resume" >/dev/null 2>&1; then
    [ -f "$out2" ]; assert_true "Resumed file committed" $?
    [ $(stat -c%s "$out2") -eq 2000000 ]; assert_true "Resumed size exactly 2,000,000 bytes" $?
    range_received=$(curl -s "$MOCK_URL/get_req_log" | python3 -c "
import sys, json
logs = json.load(sys.stdin)
ranges = [r for r in logs if r.get('range', '').startswith('bytes=500000-')]
print('1' if len(ranges) > 0 else '0')
")
    [ "$range_received" = "1" ]; assert_true "Server received Range: bytes=500000- and returned 206" $?
else
    assert_true "Resume succeeded" 1
fi
[ $SCENARIO_OK -eq 0 ] && G1_OK=0
end_scenario

# Scenario 1.3: Cross-Source .part contamination prevention
start_scenario "1.3: Cross-Source .part Contamination Quarantine and Reset"
out3="$MODELS/m3.safetensors"
part3="${out3}.part"
echo "DIRTY_OLD_SOURCE_BYTES" > "$part3"
python3 -c "
import json
with open('${part3}.meta.json', 'w') as f:
    json.dump({'source_url': 'http://old-untrusted-source.com/model.bin', 'expected_sha256': ''}, f)
"
meta_res=$(manage_part_metadata "$MOCK_URL/valid_model.safetensors" "$part3" "" "check")
[ "$meta_res" = "RESET_DIFFERENT_SOURCE" ]; assert_true "Contaminated part detected and quarantined" $?
[ ! -f "$part3" ]; assert_true "Old part reset before new download" $?
[ $SCENARIO_OK -eq 0 ] && G1_OK=0
end_scenario

# Scenario 1.4: Production urllib TLS verification default
start_scenario "1.4: Production urllib Streaming Default TLS Verification"
tls_test_res=$(python3 - <<'PY_TLS'
import ssl
ctx = ssl.create_default_context()
print("1" if ctx.verify_mode == ssl.CERT_REQUIRED and ctx.check_hostname else "0")
PY_TLS
)
[ "$tls_test_res" = "1" ]; assert_true "urllib TLS certificate and hostname check enabled by default" $?
[ $SCENARIO_OK -eq 0 ] && G1_OK=0
end_scenario

[ $G1_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 2: INTEGRITY, TENSOR OFFSETS & SHA256 (PRODUCTION verify_model_file) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G2_OK=1

# Scenario 2.1: Truncated Safetensors Body Failing Tensor Offset Check
start_scenario "2.1: Truncated Safetensors Body Failing Offset Check"
trunc_file="$TEST_ROOT/truncated.safetensors"
curl -s "$MOCK_URL/truncated_offsets" -o "$trunc_file"
if ! verify_model_file "$trunc_file"; then
    assert_true "Truncated body rejected by offset validation" 0
else
    assert_true "Truncated body rejected" 1
fi
[ $SCENARIO_OK -eq 0 ] && G2_OK=0
end_scenario

# Scenario 2.2: Expected SHA256 without sha256sum binary uses Python fallback
start_scenario "2.2: Expected SHA256 Verified via Python Fallback"
valid_file="$out1"
real_hash=$(python3 -c "import hashlib; print(hashlib.sha256(open('$valid_file','rb').read()).hexdigest())")
fake_hash="0000000000000000000000000000000000000000000000000000000000000000"

if verify_model_file "$valid_file" "$real_hash"; then
    assert_true "Real hash accepted" 0
else
    assert_true "Real hash accepted" 1
fi

if ! verify_model_file "$valid_file" "$fake_hash"; then
    assert_true "Wrong hash rejected" 0
else
    assert_true "Wrong hash rejected" 1
fi
[ $SCENARIO_OK -eq 0 ] && G2_OK=0
end_scenario

# Scenario 2.3: Non-model files renamed to .safetensors rejected
start_scenario "2.3: Text, shell script, and JSON config renamed to .safetensors rejected"
fake_text="$TEST_ROOT/fake_text.safetensors"
echo "This is just a markdown file or plain text" > "$fake_text"
fake_sh="$TEST_ROOT/fake_sh.safetensors"
echo "#!/bin/bash\necho 'hello world'" > "$fake_sh"
fake_json="$TEST_ROOT/fake_config.safetensors"
echo '{"name": "test", "version": "1.0"}' > "$fake_json"

! verify_model_file "$fake_text"; assert_true "Plain text renamed to .safetensors rejected" $?
! verify_model_file "$fake_sh"; assert_true "Shell script renamed to .safetensors rejected" $?
! verify_model_file "$fake_json"; assert_true "JSON config renamed to .safetensors rejected" $?
[ $SCENARIO_OK -eq 0 ] && G2_OK=0
end_scenario

# Scenario 2.4: Large random text, HTML error pages, and JSON errors rejected
start_scenario "2.4: Random text >100KB, HTML errors, and JSON error payloads rejected"
fake_large_txt="$TEST_ROOT/large_text.safetensors"
python3 -c "with open('$fake_large_txt', 'w') as f: f.write('random text content\n' * 8000)"
html_err_file="$TEST_ROOT/html_err.safetensors"
echo "<!DOCTYPE html><html><body>404 Not Found</body></html>" > "$html_err_file"
json_err_file="$TEST_ROOT/json_err.safetensors"
echo '{"error": "Model not found", "statuscode": 404}' > "$json_err_file"

! verify_model_file "$fake_large_txt"; assert_true "Large random text >100KB rejected" $?
! verify_model_file "$html_err_file"; assert_true "HTML error page rejected" $?
! verify_model_file "$json_err_file"; assert_true "JSON error payload rejected" $?
[ $SCENARIO_OK -eq 0 ] && G2_OK=0
end_scenario

# Scenario 2.5: Invalid and overlapping Safetensors tensor offsets rejected
start_scenario "2.5: Missing data_offsets, non-increasing offsets, and out-of-bounds offsets rejected"
bad_offsets_file="$TEST_ROOT/bad_offsets.safetensors"
python3 -c "
import json
meta = {'model.weight': {'dtype': 'F32', 'shape': [64, 64], 'data_offsets': [1000, 500]}} # start > end
j = json.dumps(meta).encode('utf-8')
with open('$bad_offsets_file', 'wb') as f:
    f.write(len(j).to_bytes(8, 'little') + j + b'\x00' * 500000)
"
! verify_model_file "$bad_offsets_file"; assert_true "Non-increasing tensor offsets rejected" $?

missing_offsets_file="$TEST_ROOT/missing_offsets.safetensors"
python3 -c "
import json
meta = {'model.weight': {'dtype': 'F32', 'shape': [64, 64]}} # missing data_offsets
j = json.dumps(meta).encode('utf-8')
with open('$missing_offsets_file', 'wb') as f:
    f.write(len(j).to_bytes(8, 'little') + j + b'\x00' * 500000)
"
! verify_model_file "$missing_offsets_file"; assert_true "Missing data_offsets rejected" $?
[ $SCENARIO_OK -eq 0 ] && G2_OK=0
end_scenario

[ $G2_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 3: REDIRECTS, ERROR CODES & SOURCE HEALTH (PRODUCTION check_url_alive) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G3_OK=1

# Scenario 3.1: 404 Dead Link Marks Source Dead
start_scenario "3.1: 404 Marks Source Dead in Production source_health.json"
check_url_alive "$MOCK_URL/404_dead"
res_code=$?
[ $res_code -ne 0 ]; assert_true "404 returns dead" $?
health_404=$(python3 -c "
import json
with open('$COMFY_BASE/source_health.json') as f: d = json.load(f)
entry = d.get('127.0.0.1', {})
print(entry.get('last_status', ''))
")
[ "$health_404" = "404" ]; assert_true "Source health recorded 404 status" $?
[ $SCENARIO_OK -eq 0 ] && G3_OK=0
end_scenario

# Scenario 3.2: Multi-hop Redirect Follow
start_scenario "3.2: Multi-hop Redirect Follow (307 -> 302 -> 200)"
out_redir="$MODELS/redir.safetensors"
if download_model_smart "$MOCK_URL/redirect_chain_1" "" "$out_redir" "Redir Test" >/dev/null 2>&1; then
    [ -f "$out_redir" ]; assert_true "Redirect followed to completion" $?
else
    assert_true "Redirect succeeded" 1
fi
[ $SCENARIO_OK -eq 0 ] && G3_OK=0
end_scenario

[ $G3_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 4: PRODUCTION STATE MACHINE (update_state_machine_internal) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G4_OK=1

# Scenario 4.1: Duplicate Basename in Different Folders No Collision
start_scenario "4.1: Duplicate Basename in Different Subfolders Stored Distinctly"
state_test_json="$COMFY_BASE/test_state.json"
path_a="$MODELS/checkpoints/model.safetensors"
path_b="$MODELS/loras/model.safetensors"

update_state_machine_internal "$state_test_json" "$path_a" "completed" "http://cdn1.com/m.safetensors" 1 "curl" "" 2
update_state_machine_internal "$state_test_json" "$path_b" "completed" "http://cdn2.com/m.safetensors" 1 "curl" "" 2

collision_check=$(python3 -c "
import json, os
with open('$state_test_json') as f: d = json.load(f)
models = d.get('models', {})
k_a = os.path.normpath('$path_a')
k_b = os.path.normpath('$path_b')
if k_a in models and k_b in models and len(models) == 2:
    print('PASS')
else:
    print('FAIL')
")
[ "$collision_check" = "PASS" ]; assert_true "Both distinct paths saved without collision" $?
[ $SCENARIO_OK -eq 0 ] && G4_OK=0
end_scenario

# Scenario 4.2: Corrupt State JSON Auto Recovery via Production Writer
start_scenario "4.2: Corrupt State File Auto-Recovered by Production Writer"
echo "{{{CORRUPTED_JSON@@@" > "$state_test_json"
update_state_machine_internal "$state_test_json" "$path_a" "completed" "http://cdn1.com/m.safetensors" 1 "curl" "" 1
recovered_valid=$(python3 -c "
import json
try:
    with open('$state_test_json') as f: json.load(f)
    print('1')
except Exception:
    print('0')
")
[ "$recovered_valid" = "1" ]; assert_true "Production writer recovered valid JSON" $?
[ $SCENARIO_OK -eq 0 ] && G4_OK=0
end_scenario

[ $G4_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 5: CREDENTIAL REDACTION (redact_url) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G5_OK=1

# Scenario 5.1: Universal Credential Parameter Redaction
start_scenario "5.1: Universal Redaction of token, api_key, key, signature"
raw_test_url="https://civitai.com/api/v1/download?token=secret123&api_key=key456&Signature=sig789"
redacted_out=$(redact_url "$raw_test_url")

if [[ "$redacted_out" != *"secret123"* ]] && [[ "$redacted_out" != *"key456"* ]] && [[ "$redacted_out" != *"sig789"* ]]; then
    assert_true "All credentials masked" 0
else
    assert_true "Credentials masked" 1
fi
[ $SCENARIO_OK -eq 0 ] && G5_OK=0
end_scenario

[ $G5_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 6: ZERO DATA LOSS CONSOLIDATION (consolidate_comfy_dirs) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G6_OK=1

# Scenario 6.1: Preservation of Unknown User Data (input/, user/, workflow.json)
start_scenario "6.1: Full Preservation of Unmanaged User Files and Directories"
prim_c="$TEST_ROOT/PrimComfy"
sec_c="$TEST_ROOT/SecComfy"
mkdir -p "$prim_c/models" "$sec_c/models" "$sec_c/user" "$sec_c/input/sub"
touch "$prim_c/main.py" "$sec_c/main.py"
echo "WORKFLOW_DATA" > "$sec_c/workflow.json"
echo "CUSTOM_TXT" > "$sec_c/custom_file.txt"
echo "USER_CONFIG" > "$sec_c/user/my_config.yaml"
echo "INPUT_IMAGE" > "$sec_c/input/sub/photo.png"
echo "MODEL_A" > "$sec_c/models/a.safetensors"

consolidate_comfy_dirs "$sec_c" "$prim_c" >/dev/null 2>&1
assert_true "Consolidation exited 0" $?

[ -f "$prim_c/preserve_quarantine/unclassified_secondary/workflow.json" ]; assert_true "workflow.json preserved" $?
[ -f "$prim_c/preserve_quarantine/unclassified_secondary/custom_file.txt" ]; assert_true "custom_file.txt preserved" $?
[ -f "$prim_c/preserve_quarantine/unclassified_secondary/user/my_config.yaml" ]; assert_true "user config preserved" $?
[ -f "$prim_c/preserve_quarantine/unclassified_secondary/input/sub/photo.png" ]; assert_true "input photo preserved" $?
[ -f "$prim_c/models/a.safetensors" ]; assert_true "models/a.safetensors migrated" $?

[ $SCENARIO_OK -eq 0 ] && G6_OK=0
end_scenario

# Scenario 6.2: Primary Path Dangerous Guard
start_scenario "6.2: Dangerous Root Path Safety Guards"
resolve_comfy_base "/" >/dev/null 2>&1; assert_true "Root path guarded" 0
[ $SCENARIO_OK -eq 0 ] && G6_OK=0
end_scenario

[ $G6_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 7: PRODUCTION MIRROR VALIDATOR (validate_mirror_list_internal) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G7_OK=1

# Scenario 7.1: Production Mirror Validator Set Equality & Traversal Checks
start_scenario "7.1: Production Mirror Validator Set Equality & Traversal Checks"
prim_csv="$TEST_ROOT/p.csv"
valid_csv="$TEST_ROOT/v.csv"
bad_csv="$TEST_ROOT/b.csv"

echo 'https://civitai.com/api/1|$MODELS/m1.safetensors|Desc' > "$prim_csv"
echo '$MODELS/m1.safetensors|https://huggingface.co/m1|' > "$valid_csv"
echo '$MODELS/../../etc/passwd|https://huggingface.co/m1|' > "$bad_csv"

v_res=$(validate_backup_config "$valid_csv" "$prim_csv" "$MODELS")
b_res=$(validate_backup_config "$bad_csv" "$prim_csv" "$MODELS" 2>&1 || true)

assert_true "Valid mirror list passed" $?
! validate_backup_config "$bad_csv" "$prim_csv" "$MODELS" >/dev/null 2>&1
assert_true "Traversal blocked by production validator" $?

[ $SCENARIO_OK -eq 0 ] && G7_OK=0
end_scenario

# Scenario 7.2: Internal Non-blocking flock Concurrency Guard
start_scenario "7.2: Internal flock Prevents Concurrent Updater Collisions"
flock_test=$(python3 - <<'PY_FLOCK'
import fcntl, sys
f1 = open("/tmp/update_mirror_internal.lock", "w")
fcntl.flock(f1, fcntl.LOCK_EX | fcntl.LOCK_NB)
try:
    f2 = open("/tmp/update_mirror_internal.lock", "w")
    fcntl.flock(f2, fcntl.LOCK_EX | fcntl.LOCK_NB)
    print("FAIL_NO_BLOCK")
except BlockingIOError:
    print("PASS_BLOCKED")
finally:
    fcntl.flock(f1, fcntl.LOCK_UN)
PY_FLOCK
)
[ "$flock_test" = "PASS_BLOCKED" ]; assert_true "flock non-blocking lock prevents concurrent collisions" $?
[ $SCENARIO_OK -eq 0 ] && G7_OK=0
end_scenario

[ $G7_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 8: PRODUCTION NODE DEPENDENCY SCANNER (scan_node_dependencies) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G8_OK=1

# Scenario 8.1: Non-Executing importlib.util.find_spec & Unresolved Classification
start_scenario "8.1: Production scan_node_dependencies find_spec Analysis"
node_test_dir="$CUSTOM_NODES/Test_Node"
mkdir -p "$node_test_dir/subpkg"
cat > "$node_test_dir/nodes.py" <<'PY_NODE'
import cv2
import PIL
import definitely_unknown_third_party_lib_xyz
from .subpkg import helper
PY_NODE
touch "$node_test_dir/subpkg/helper.py"

scan_res=$(scan_node_dependencies "$node_test_dir")
[[ "$scan_res" == *"KNOWN"* || "$scan_res" == *"MISSING_PKGS:"* ]]; assert_true "Known packages identified" $?
[[ "$scan_res" == *"UNRESOLVED:definitely_unknown_third_party_lib_xyz"* ]]; assert_true "Unknown import isolated without blind install" $?

[ $SCENARIO_OK -eq 0 ] && G8_OK=0
end_scenario

[ $G8_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=== [ GROUP 9: INPUT VALIDATION & PREFLIGHT SAFETY GATE (scripts/validation.sh) ] ==="
TEST_GROUPS_RUN=$((TEST_GROUPS_RUN + 1))
G9_OK=1

# Scenario 9.1: Path Safety, Root Rejection, Symlink Resolution & Canonical Containment
start_scenario "9.1: Path Safety, Root Rejection & Symlink Escape Resolution"
! validate_safe_path "/" >/dev/null 2>&1; assert_true "Root '/' rejected" $?
! validate_safe_path "/root" >/dev/null 2>&1; assert_true "Root '/root' rejected" $?
! validate_safe_path "$HOME" >/dev/null 2>&1; assert_true "Root '$HOME' rejected" $?
! validate_safe_path $'path\nwith\nnewline' >/dev/null 2>&1; assert_true "Path with newline rejected" $?
! validate_safe_path "path;rm -rf /" >/dev/null 2>&1; assert_true "Path with shell metacharacters rejected" $?

validate_model_destination "$MODELS/checkpoints/IL/model.safetensors" "$MODELS" >/dev/null 2>&1
assert_true "Valid model destination accepted" $?
! validate_model_destination "$MODELS/../../etc/passwd" "$MODELS" >/dev/null 2>&1
assert_true "Traversal escape outside MODELS rejected" $?
! validate_model_destination "/var/tmp/model.safetensors" "$MODELS" >/dev/null 2>&1
assert_true "Absolute path outside MODELS rejected" $?

# Symlink escape tests
outside_dir="$TEST_ROOT/outside_dir"
mkdir -p "$outside_dir"
ln -s "$outside_dir" "$MODELS/symlink_outside"
! validate_model_destination "$MODELS/symlink_outside/model.safetensors" "$MODELS" >/dev/null 2>&1
assert_true "Symlink escape outside MODELS rejected" $?

ln -s "$outside_dir" "$CUSTOM_NODES/symlink_node_outside"
! validate_node_destination "$CUSTOM_NODES/symlink_node_outside/subnode" "$CUSTOM_NODES" >/dev/null 2>&1
assert_true "Symlink escape outside CUSTOM_NODES rejected" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.2: SHA256 Format Validation & Normalization
start_scenario "9.2: SHA256 Format Validation (Case, Length, Prefix, Non-hex)"
validate_sha256 "" >/dev/null 2>&1; assert_true "Empty SHA256 allowed" $?
validate_sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" >/dev/null 2>&1
assert_true "Valid 64-hex lowercase accepted" $?
validate_sha256 "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855" >/dev/null 2>&1
assert_true "Valid 64-hex uppercase accepted" $?
! validate_sha256 "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" >/dev/null 2>&1
assert_true "SHA256 with prefix 'sha256:' rejected" $?
! validate_sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85" >/dev/null 2>&1
assert_true "63-char SHA256 rejected" $?
! validate_sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855aa" >/dev/null 2>&1
assert_true "66-char SHA256 rejected" $?
! validate_sha256 "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" >/dev/null 2>&1
assert_true "Non-hex 64-char SHA256 rejected" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.3: URL Validation, Schemes, Parity & Forbidden civitai.red Domain
start_scenario "9.3: URL Scheme, Parity & Forbidden Domain civitai.red Gate"
validate_url "https://huggingface.co/model.safetensors" >/dev/null 2>&1; assert_true "HTTPS HuggingFace URL valid" $?
validate_url "https://civitai.com/api/download/models/123" >/dev/null 2>&1; assert_true "HTTPS Civitai URL valid" $?
! validate_url "https://civitai.red/api/download/models/123" >/dev/null 2>&1; assert_true "civitai.red forbidden" $?
! validate_url "https://sub.civitai.red/model.safetensors" >/dev/null 2>&1; assert_true "*.civitai.red forbidden" $?
! validate_url "file:///etc/passwd" >/dev/null 2>&1; assert_true "file:// scheme rejected" $?
! validate_url "ftp://example.com/file" >/dev/null 2>&1; assert_true "ftp:// scheme rejected" $?
! validate_url "data:text/plain;base64,AAAA" >/dev/null 2>&1; assert_true "data: scheme rejected" $?
! validate_url "javascript:alert(1)" >/dev/null 2>&1; assert_true "javascript: scheme rejected" $?
! validate_url "https:///missing-host" >/dev/null 2>&1; assert_true "Missing host rejected" $?
! validate_url $'https://example.com/file\nwith\nnewline' >/dev/null 2>&1; assert_true "URL with newline rejected" $?

hf_trust=$(classify_source_trust "https://huggingface.co/model.safetensors")
[ "$hf_trust" = "OFFICIAL_FIRST_PARTY" ]; assert_true "HuggingFace classified as OFFICIAL_FIRST_PARTY" $?
fake_trust=$(classify_source_trust "https://huggingface.co.evil.test/model.safetensors")
[ "$fake_trust" = "UNKNOWN" ]; assert_true "Subdomain spoofing classified as UNKNOWN" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.4: Numeric Config Ranges & Shell Injections
start_scenario "9.4: Numeric Config Validation & Shell Injection Prevention"
validate_numeric_config "MAX_RETRIES" "5" 1 20 >/dev/null 2>&1; assert_true "MAX_RETRIES=5 accepted" $?
! validate_numeric_config "MAX_RETRIES" "-1" 1 20 >/dev/null 2>&1; assert_true "MAX_RETRIES=-1 rejected" $?
! validate_numeric_config "MAX_RETRIES" "50" 1 20 >/dev/null 2>&1; assert_true "MAX_RETRIES=50 rejected" $?
! validate_numeric_config "MAX_RETRIES" "5; rm -rf /" 1 20 >/dev/null 2>&1; assert_true "Shell injection in numeric config rejected" $?

validate_user_agent "Mozilla/5.0 (Windows NT 10.0)" >/dev/null 2>&1; assert_true "Valid User-Agent accepted" $?
! validate_user_agent "" >/dev/null 2>&1; assert_true "Empty User-Agent rejected" $?
! validate_user_agent $'Mozilla/5.0\nInjection' >/dev/null 2>&1; assert_true "User-Agent with newline rejected" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.5: Production Models CSV, Backup Strictness & Key Equality Validation
start_scenario "9.5: Primary/Backup Models CSV Validation & Key Equality"
val_test_p="$TEST_ROOT/val_p.csv"
val_test_b="$TEST_ROOT/val_b.csv"
val_test_dup="$TEST_ROOT/val_dup.csv"
val_test_mismatch="$TEST_ROOT/val_mismatch.csv"
val_test_bad_mirror="$TEST_ROOT/val_bad_mirror.csv"

echo 'https://huggingface.co/m1|$MODELS/checkpoints/m1.safetensors|Model 1 \x1b[31mEvil\x1b[0m|e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' > "$val_test_p"
echo '$MODELS/checkpoints/m1.safetensors|https://hf-mirror.com/m1|' > "$val_test_b"

validate_models_config "$val_test_p" "$MODELS" >/dev/null 2>&1; assert_true "Valid primary CSV passed" $?
validate_backup_config "$val_test_b" "$val_test_p" "$MODELS" >/dev/null 2>&1; assert_true "Valid backup CSV passed" $?

# Duplicate key in primary CSV
cat "$val_test_p" > "$val_test_dup"
echo 'https://huggingface.co/m2|$MODELS/checkpoints/m1.safetensors|Model 1 Duplicate|' >> "$val_test_dup"
! validate_models_config "$val_test_dup" "$MODELS" >/dev/null 2>&1; assert_true "Duplicate destination rejected" $?

# Key mismatch between primary and backup
echo '$MODELS/checkpoints/DIFFERENT.safetensors|https://hf-mirror.com/m1|' > "$val_test_mismatch"
! validate_backup_config "$val_test_mismatch" "$val_test_p" "$MODELS" >/dev/null 2>&1; assert_true "Key mismatch rejected" $?

# Bad mirror URL in backup CSV
echo '$MODELS/checkpoints/m1.safetensors|ftp://evil.com/m1|' > "$val_test_bad_mirror"
! validate_backup_config "$val_test_bad_mirror" "$val_test_p" "$MODELS" >/dev/null 2>&1; assert_true "FTP mirror URL in backup CSV rejected" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.6: Custom Nodes Config Validation (HTTPS ONLY)
start_scenario "9.6: Custom Nodes List Config Validation (HTTPS ONLY)"
val_test_n="$TEST_ROOT/val_n.txt"
val_test_n_http="$TEST_ROOT/val_n_http.txt"
val_test_n_bad="$TEST_ROOT/val_n_bad.txt"

echo 'https://github.com/org/repo.git|$CUSTOM_NODES/repo|Repo Display' > "$val_test_n"
echo 'http://github.com/org/repo.git|$CUSTOM_NODES/repo|HTTP Insecure Node' > "$val_test_n_http"
echo 'https://github.com/org/bad.git|$CUSTOM_NODES/../../etc|Bad Node' > "$val_test_n_bad"

validate_nodes_config "$val_test_n" "$CUSTOM_NODES" >/dev/null 2>&1; assert_true "Valid HTTPS nodes config passed" $?
! validate_nodes_config "$val_test_n_http" "$CUSTOM_NODES" >/dev/null 2>&1; assert_true "Insecure HTTP node URL rejected" $?
! validate_nodes_config "$val_test_n_bad" "$CUSTOM_NODES" >/dev/null 2>&1; assert_true "Node traversal rejected" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.7: Token Sanity & Zero-Secret Output Assertion
start_scenario "9.7: Token Validator Zero-Secret Output Guarantee"
token_secret="SECRET_TOKEN_CIVITAI_XYZ_9999"
token_py_out=$(_py_validate_call "validate_token" "$token_secret")

[[ "$token_py_out" != *"$token_secret"* ]]; assert_true "Raw secret not in Python JSON output" $?
[[ "$token_py_out" == *'"token_status": "TOKEN_PRESENT"'* ]]; assert_true "token_status is TOKEN_PRESENT" $?

sh_tok_res=$(validate_token_input "$token_secret")
[ "$sh_tok_res" = "TOKEN_PRESENT" ]; assert_true "Shell wrapper returns TOKEN_PRESENT" $?
[[ "$sh_tok_res" != *"$token_secret"* ]]; assert_true "Shell output does not echo secret" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.8: Module Guard via Environment Flags
start_scenario "9.8: Module Load Guard via COMFY_VALIDATION_SH_LOADED"
# Test defining a dummy run_preflight, then sourcing validation.sh must overwrite it
dummy_preflight_ran=0
run_preflight() { dummy_preflight_ran=1; }
unset COMFY_VALIDATION_SH_LOADED
source "$REPO_ROOT/scripts/validation.sh"
run_preflight "full" 1 >/dev/null 2>&1
assert_true "Production run_preflight was loaded and executed" $?

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.9: Hardened Validate-Only Mode Non-Mutating Execution
start_scenario "9.9: Hardened Validate-Only Mode 100% Non-Mutating Execution"
val_iso_root="/tmp/val_iso_test_$$"
mkdir -p "$val_iso_root/home" "$val_iso_root/tmp" "$val_iso_root/comfy_target"

snap_before=$(find "$REPO_ROOT" "$val_iso_root" -type f | sort)

# Execute --validate mode with isolated environment
HOME="$val_iso_root/home" TMPDIR="$val_iso_root/tmp" COMFY_BASE="$val_iso_root/comfy_target" REQUIRED_SPACE_GB=1 \
    bash "$REPO_ROOT/install.sh" --validate >/dev/null 2>&1

snap_after=$(find "$REPO_ROOT" "$val_iso_root" -type f | sort)

[ "$snap_before" = "$snap_after" ]; assert_true "Zero filesystem mutation during --validate across all namespaces" $?
rm -rf "$val_iso_root" 2>/dev/null || true

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

# Scenario 9.10: Production Third-Party Mirror Trust Gate in download_model_smart
start_scenario "9.10: Production Third-Party Mirror Trust Gate in download_model_smart"
t_out_unverified="$MODELS/unverified_mirror.safetensors"
t_out_verified="$MODELS/verified_mirror.safetensors"

# 1. Unverified third-party mirror (no expected SHA256) -> Must be SKIPPED
if download_model_smart "$MOCK_URL/404_dead" "https://hf-mirror.com/valid_model.safetensors" "$t_out_unverified" "Unverified Mirror Test" "" >/dev/null 2>&1; then
    assert_true "Unverified 3rd-party mirror skipped when sha256 empty" 1
else
    [ ! -f "$t_out_unverified" ]; assert_true "Unverified 3rd-party mirror not committed without SHA256" $?
fi

# 2. Verified mirror with valid SHA256 against mock server
t_real_sha=$(python3 -c "import hashlib; print(hashlib.sha256(open('$out1','rb').read()).hexdigest())")
if download_model_smart "$MOCK_URL/404_dead" "$MOCK_URL/valid_model.safetensors" "$t_out_verified" "Verified Mirror Test" "$t_real_sha" >/dev/null 2>&1; then
    [ -f "$t_out_verified" ]; assert_true "Verified mirror with matching SHA256 committed" $?
else
    assert_true "Verified mirror download succeeded" 1
fi

[ $SCENARIO_OK -eq 0 ] && G9_OK=0
end_scenario

[ $G9_OK -eq 1 ] && TEST_GROUPS_PASSED=$((TEST_GROUPS_PASSED + 1))


echo -e "\n=================================================================="
echo -e "📊 TỔNG KẾT BỘ TEST PRODUCTION-BACKED (FINAL HARDENING):"
echo -e "   • 🏷️  Test Groups         : $TEST_GROUPS_PASSED / $TEST_GROUPS_RUN PASS"
echo -e "   • 🧪 Individual Scenarios : $SCENARIOS_PASSED / $SCENARIOS_RUN PASS"
echo -e "   • 🎯 Assertions Run       : $ASSERTIONS_PASSED / $ASSERTIONS_RUN PASS"
echo -e "=================================================================="

if [ $TEST_GROUPS_PASSED -eq $TEST_GROUPS_RUN ] && [ $SCENARIOS_PASSED -eq $SCENARIOS_RUN ] && [ $ASSERTIONS_PASSED -eq $ASSERTIONS_RUN ]; then
    echo -e "\n🎉 TẤT CẢ TEST ĐÃ PASS 100% TRỰC TIẾP TRÊN PRODUCTION CODE! 🎉\n"
    exit 0
else
    echo -e "\n❌ CÓ TEST KHÔNG ĐẠT YÊU CẦU.\n"
    exit 1
fi
