#!/bin/bash
# ================================================================================================================================
# REUSABLE INPUT VALIDATION & PREFLIGHT SAFETY GATE FOR COMFYUI-SETUP1
# Provides pure, reusable validation helpers for CLI, environment, config files, URLs, paths, SHA256, and boundary revalidation.
# ================================================================================================================================

if [ "${COMFY_VALIDATION_SH_LOADED:-}" = "1" ]; then
    return 0
fi
export COMFY_VALIDATION_SH_LOADED=1
export COMFY_VALIDATION_SH_VERSION="1"

# Ensure common colors are available
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[0;33m}"
BLUE="${BLUE:-\033[0;34m}"
MAGENTA="${MAGENTA:-\033[0;35m}"
CYAN="${CYAN:-\033[0;36m}"
NC="${NC:-\033[0m}"

# Limits for config protection (applied to both local preflight and remote updates)
MAX_CONFIG_FILE_SIZE_BYTES=5242880 # 5 MB
MAX_CONFIG_ROWS=5000
MAX_CONFIG_LINE_LENGTH=16384

# ================================================================================================================================
# 1. STANDALONE PYTHON VALIDATOR BACKEND
# ================================================================================================================================

# Execute a Python validation operation and return JSON {status: "pass"|"fail", error_code: "...", error_msg: "...", data: ...}
_py_validate_call() {
    local op="$1"
    shift
    python3 - "$op" "$@" <<'PY_VAL'
import sys, os, re, json, urllib.parse

op = sys.argv[1]
args = sys.argv[2:]

MAX_CONFIG_FILE_SIZE_BYTES = 5242880 # 5 MB
MAX_CONFIG_ROWS = 5000
MAX_CONFIG_LINE_LENGTH = 16384

def make_res(status, code="", msg="", data=None):
    return json.dumps({"status": status, "error_code": code, "error_msg": msg, "data": data})

def sanitize_str(s):
    if not isinstance(s, str):
        return ""
    # Strip ANSI escape sequences
    s = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', s)
    # Strip all C0 control characters (0x00-0x1F) and DEL (0x7F)
    s = re.sub(r'[\x00-\x1f\x7f]', '', s)
    return s.strip()

def resolve_canonical_path(base_dir, target_path):
    base_real = os.path.realpath(os.path.abspath(os.path.expanduser(base_dir)))
    target_abs = os.path.abspath(os.path.expanduser(target_path))

    # Walk up target_abs to find nearest existing parent and realpath it (symlink resolution)
    curr = target_abs
    suffix_parts = []
    while not os.path.exists(curr) and curr != os.path.dirname(curr):
        suffix_parts.insert(0, os.path.basename(curr))
        curr = os.path.dirname(curr)

    parent_real = os.path.realpath(curr)
    canonical_target = os.path.normpath(os.path.join(parent_real, *suffix_parts)) if suffix_parts else parent_real
    return base_real, canonical_target

def validate_url_value(raw_url, allowed_schemes=('http', 'https')):
    if not raw_url or not str(raw_url).strip():
        return False, "E_URL_EMPTY", "URL cannot be empty", None

    clean_url = str(raw_url).strip()
    if any(c in clean_url for c in ['\n', '\r', '\0', '\t', ' ']) or '\\n' in clean_url or '\\r' in clean_url or '\\0' in clean_url:
        return False, "E_CONTROL_CHAR_INJECTION", "URL contains control characters or whitespace", None

    if re.search(r'[\x00-\x1f\x7f]', clean_url):
        return False, "E_CONTROL_CHAR_INJECTION", "URL contains unprintable control characters", None

    try:
        parsed = urllib.parse.urlparse(clean_url)
    except Exception as e:
        return False, "E_INVALID_URL", f"Cannot parse URL: {str(e)}", None

    if not parsed.scheme or parsed.scheme.lower() not in [s.lower() for s in allowed_schemes]:
        allowed_str = "/".join([s.upper() for s in allowed_schemes])
        return False, "E_INVALID_URL_SCHEME", f"Unsupported URL scheme '{parsed.scheme}'. Only {allowed_str} allowed.", None

    hostname = (parsed.hostname or "").lower().strip()
    if not hostname:
        return False, "E_INVALID_HOSTNAME", "URL missing hostname", None

    # Forbidden domain checks (civitai.red and subdomains)
    if hostname == "civitai.red" or hostname.endswith(".civitai.red"):
        return False, "E_FORBIDDEN_DOMAIN", f"Forbidden domain '{hostname}' is not permitted.", None

    # Source Trust Classification
    trust_class = "UNKNOWN"
    if (hostname == "civitai.com" or hostname.endswith(".civitai.com") or
        hostname == "huggingface.co" or hostname.endswith(".huggingface.co") or
        hostname == "hf.co" or hostname.endswith(".hf.co") or
        hostname == "github.com" or hostname.endswith(".github.com") or
        hostname == "raw.githubusercontent.com" or hostname == "objects.githubusercontent.com" or
        hostname == "githubusercontent.com" or hostname.endswith(".githubusercontent.com")):
        trust_class = "OFFICIAL_FIRST_PARTY"
    elif hostname in ["hf-mirror.com", "ghproxy.net", "gh-proxy.com"] or any(hostname.endswith("." + m) for m in ["hf-mirror.com", "ghproxy.net", "gh-proxy.com"]):
        trust_class = "THIRD_PARTY_MIRROR"
    else:
        trust_class = "UNKNOWN"

    return True, "", "", {
        "url": clean_url,
        "hostname": hostname,
        "scheme": parsed.scheme.lower(),
        "trust_class": trust_class
    }

# ── 1. Path Safety & Containment ─────────────────────────────────────────────
if op == "validate_safe_path":
    path = args[0] if len(args) > 0 else ""
    if not path or not path.strip():
        print(make_res("fail", "E_PATH_EMPTY", "Path cannot be empty"))
        sys.exit(0)

    # Check control characters / newlines
    if any(c in path for c in ['\n', '\r', '\0', '\t', ';', '&', '`', '$', '<', '>']) or '\\n' in path or '\\r' in path or '\\0' in path:
        print(make_res("fail", "E_CONTROL_CHAR_INJECTION", f"Path contains illegal control/shell characters: {repr(path)}"))
        sys.exit(0)

    try:
        norm = os.path.abspath(os.path.expanduser(path.strip()))
        real = os.path.realpath(norm)
    except Exception as e:
        print(make_res("fail", "E_PATH_INVALID", f"Cannot resolve path: {str(e)}"))
        sys.exit(0)

    # Reject dangerous system roots
    dangerous_roots = {
        "/", "/root", "/workspace", "/app", "/content", "/home", "/etc", "/var", "/usr", "/bin", "/sbin", "/tmp", "/kaggle/working"
    }
    user_home = os.path.realpath(os.path.expanduser("~"))
    if user_home:
        dangerous_roots.add(user_home)

    if norm in dangerous_roots or real in dangerous_roots:
        print(make_res("fail", "E_PATH_UNSAFE_ROOT", f"Path refers directly to a critical system root or home directory: {norm}"))
        sys.exit(0)

    if len(norm) <= 3:
        print(make_res("fail", "E_PATH_TOO_SHORT", f"Path is too short and dangerous: {norm}"))
        sys.exit(0)

    print(make_res("pass", data={"normalized": norm, "canonical": real}))
    sys.exit(0)

elif op == "validate_containment":
    base_dir = args[0] if len(args) > 0 else ""
    target_path = args[1] if len(args) > 1 else ""
    scope_name = args[2] if len(args) > 2 else "MODELS"

    if not base_dir or not target_path:
        print(make_res("fail", "E_PATH_EMPTY", "Base or target path empty"))
        sys.exit(0)

    if any(c in target_path for c in ['\n', '\r', '\0', ';', '&', '`', '<', '>']) or '\\n' in target_path or '\\r' in target_path or '\\0' in target_path:
        print(make_res("fail", "E_CONTROL_CHAR_INJECTION", f"Target path contains illegal characters: {repr(target_path)}"))
        sys.exit(0)

    try:
        base_real, canonical_target = resolve_canonical_path(base_dir, target_path)

        # Use commonpath containment with symlink-aware canonical target
        common = os.path.commonpath([base_real, canonical_target])
        if common != base_real:
            print(make_res("fail", f"E_PATH_OUTSIDE_{scope_name}", f"Path '{target_path}' escapes boundary '{base_dir}' via traversal or symlink (canonical target: '{canonical_target}', base: '{base_real}')"))
            sys.exit(0)

        if canonical_target == base_real:
            print(make_res("fail", f"E_PATH_EQUALS_ROOT_{scope_name}", f"Path cannot be identical to root directory '{base_dir}'"))
            sys.exit(0)

        print(make_res("pass", data={"base": base_real, "target": canonical_target}))
        sys.exit(0)
    except Exception as e:
        print(make_res("fail", "E_PATH_TRAVERSAL", f"Path resolution failed: {str(e)}"))
        sys.exit(0)

# ── 2. URL & Domain Trust Validation ─────────────────────────────────────────
elif op == "validate_url":
    raw_url = args[0] if len(args) > 0 else ""
    allowed = args[1].split(',') if len(args) > 1 and args[1] else ('http', 'https')
    ok, code, msg, data = validate_url_value(raw_url, allowed_schemes=allowed)
    if not ok:
        print(make_res("fail", code, msg))
    else:
        print(make_res("pass", data=data))
    sys.exit(0)

# ── 3. SHA256 Format Validation ──────────────────────────────────────────────
elif op == "validate_sha256":
    raw_sha = args[0] if len(args) > 0 else ""
    if not raw_sha or not raw_sha.strip():
        print(make_res("pass", data={"sha256": ""}))
        sys.exit(0)

    clean_sha = raw_sha.strip().lower()
    if clean_sha.startswith("sha256:"):
        print(make_res("fail", "E_SHA256_FORMAT", "SHA256 must not include 'sha256:' prefix"))
        sys.exit(0)

    if len(clean_sha) != 64 or not re.match(r'^[a-f0-9]{64}$', clean_sha):
        print(make_res("fail", "E_SHA256_FORMAT", f"Invalid SHA256 hex string format (len={len(clean_sha)})"))
        sys.exit(0)

    print(make_res("pass", data={"sha256": clean_sha}))
    sys.exit(0)

# ── 4. Numeric Configuration Bounding ────────────────────────────────────────
elif op == "validate_numeric":
    name = args[0] if len(args) > 0 else "CONFIG"
    val_str = args[1] if len(args) > 1 else ""
    min_v = int(args[2]) if len(args) > 2 else 0
    max_v = int(args[3]) if len(args) > 3 else 999999

    if val_str is None or val_str == "":
        print(make_res("fail", "E_INVALID_NUMERIC_CONFIG", f"{name} cannot be empty"))
        sys.exit(0)

    val_str = str(val_str).strip()
    if not re.match(r'^-?[0-9]+$', val_str):
        print(make_res("fail", "E_INVALID_NUMERIC_CONFIG", f"{name} must be an integer, got: {repr(val_str)}"))
        sys.exit(0)

    try:
        val_int = int(val_str)
    except Exception:
        print(make_res("fail", "E_INVALID_NUMERIC_CONFIG", f"{name} integer overflow/parse error: {val_str}"))
        sys.exit(0)

    if val_int < min_v or val_int > max_v:
        print(make_res("fail", "E_NUMERIC_OUT_OF_BOUNDS", f"{name}={val_int} is out of safe range [{min_v}..{max_v}]"))
        sys.exit(0)

    print(make_res("pass", data={"name": name, "value": val_int}))
    sys.exit(0)

# ── 5. User-Agent Validation ────────────────────────────────────────────────
elif op == "validate_user_agent":
    ua = args[0] if len(args) > 0 else ""
    if not ua or not ua.strip():
        print(make_res("fail", "E_INVALID_USER_AGENT", "USER_AGENT cannot be empty"))
        sys.exit(0)

    if any(c in ua for c in ['\n', '\r', '\0']) or re.search(r'[\x00-\x1f\x7f]', ua):
        print(make_res("fail", "E_CONTROL_CHAR_INJECTION", "USER_AGENT contains newline or control characters"))
        sys.exit(0)

    print(make_res("pass", data={"user_agent": ua.strip()}))
    sys.exit(0)

# ── 6. Token Sanity & Secret Handling (NEVER SERIALIZE TOKEN) ────────────────
elif op == "validate_token":
    raw_token = args[0] if len(args) > 0 else ""
    if not raw_token or not str(raw_token).strip():
        print(make_res("pass", data={"token_status": "TOKEN_EMPTY"}))
        sys.exit(0)

    clean_token = str(raw_token).strip()
    # Clean known accidental prefixes
    if clean_token.startswith("token="): clean_token = clean_token[6:]
    elif clean_token.startswith("?token="): clean_token = clean_token[7:]
    elif clean_token.startswith("&token="): clean_token = clean_token[7:]

    clean_token = clean_token.strip()
    if any(c in clean_token for c in ['\n', '\r', '\0', ' ', '\t']) or re.search(r'[\x00-\x1f\x7f]', clean_token):
        print(make_res("fail", "E_INVALID_TOKEN_INPUT", "Civitai token contains illegal whitespace or control characters", data={"token_status": "TOKEN_INVALID_FORMAT"}))
        sys.exit(0)

    print(make_res("pass", data={"token_status": "TOKEN_PRESENT"}))
    sys.exit(0)

# ── 7. Primary Models CSV Validation ─────────────────────────────────────────
elif op == "validate_models_config":
    csv_path = args[0] if len(args) > 0 else ""
    models_base = args[1] if len(args) > 1 else ""

    if not os.path.exists(csv_path):
        print(make_res("fail", "E_CONFIG_MISSING", f"Models config file not found: {csv_path}"))
        sys.exit(0)

    file_size = os.path.getsize(csv_path)
    if file_size > MAX_CONFIG_FILE_SIZE_BYTES:
        print(make_res("fail", "E_CONFIG_TOO_LARGE", f"Models config file size ({file_size} bytes) exceeds limit ({MAX_CONFIG_FILE_SIZE_BYTES} bytes)"))
        sys.exit(0)

    errors = []
    warnings = []
    entries = []
    seen_destinations = set()

    with open(csv_path, 'r', encoding='utf-8-sig', errors='replace') as f:
        lines = f.readlines()

    if len(lines) > MAX_CONFIG_ROWS:
        print(make_res("fail", "E_CONFIG_ROW_LIMIT", f"Config contains {len(lines)} rows, exceeding max limit {MAX_CONFIG_ROWS}"))
        sys.exit(0)

    for line_num, line in enumerate(lines, 1):
        if len(line) > MAX_CONFIG_LINE_LENGTH:
            errors.append({"line": line_num, "code": "E_CONFIG_LINE_TOO_LONG", "msg": f"Line {line_num} exceeds {MAX_CONFIG_LINE_LENGTH} limit"})
            continue

        raw_line = line.strip().replace('\r', '')
        if not raw_line or raw_line.startswith('#'):
            continue

        parts = [p.strip() for p in raw_line.split('|')]
        if len(parts) < 3:
            errors.append({"line": line_num, "code": "E_MALFORMED_ROW", "msg": f"Line {line_num} has fewer than 3 fields"})
            continue

        url = parts[0]
        dest = parts[1]
        desc = parts[2] if len(parts) > 2 else ""
        sha = parts[3] if len(parts) > 3 else ""

        # Validate URL via unified helper
        u_ok, u_code, u_msg, u_data = validate_url_value(url, allowed_schemes=('http', 'https'))
        if not u_ok:
            errors.append({"line": line_num, "code": u_code, "msg": f"Line {line_num} URL error: {u_msg}"})

        # Validate Destination
        if not dest.startswith("$MODELS/"):
            errors.append({"line": line_num, "code": "E_INVALID_DESTINATION_PREFIX", "msg": f"Line {line_num} destination must start with $MODELS/"})
        elif '..' in dest or any(c in dest for c in [';', '&', '`', '$(']):
            errors.append({"line": line_num, "code": "E_PATH_TRAVERSAL", "msg": f"Line {line_num} path traversal or injection in destination"})
        else:
            if models_base:
                resolved_dest = dest.replace('$MODELS', models_base)
                try:
                    b_real, c_dest = resolve_canonical_path(models_base, resolved_dest)
                    common = os.path.commonpath([b_real, c_dest])
                    if common != b_real:
                        errors.append({"line": line_num, "code": "E_PATH_OUTSIDE_MODELS", "msg": f"Line {line_num} destination escapes MODELS boundary via traversal or symlink"})
                except Exception as e:
                    errors.append({"line": line_num, "code": "E_PATH_TRAVERSAL", "msg": f"Line {line_num} path resolution error: {str(e)}"})

        # Unique destination check
        if dest in seen_destinations:
            errors.append({"line": line_num, "code": "E_DUPLICATE_MODEL_KEY", "msg": f"Line {line_num} duplicate destination key '{dest}'"})
        seen_destinations.add(dest)

        # Validate SHA256 format if present
        if sha:
            sha_clean = sha.strip().lower()
            if len(sha_clean) != 64 or not re.match(r'^[a-f0-9]{64}$', sha_clean):
                errors.append({"line": line_num, "code": "E_SHA256_FORMAT", "msg": f"Line {line_num} invalid SHA256 format for '{dest}'"})

        entries.append({"url": url, "destination": dest, "description": sanitize_str(desc), "sha256": sha.strip().lower()})

    status = "pass" if not errors else "fail"
    print(json.dumps({"status": status, "errors": errors, "warnings": warnings, "data": {"count": len(entries), "keys": sorted(list(seen_destinations)), "entries": entries}}))
    sys.exit(0)

# ── 8. Backup Models CSV & Key Equality Validation ───────────────────────────
elif op == "validate_backup_config":
    backup_csv = args[0] if len(args) > 0 else ""
    primary_csv = args[1] if len(args) > 1 else ""
    models_base = args[2] if len(args) > 2 else ""

    if not os.path.exists(backup_csv):
        print(make_res("fail", "E_CONFIG_MISSING", f"Backup config file not found: {backup_csv}"))
        sys.exit(0)

    file_size = os.path.getsize(backup_csv)
    if file_size > MAX_CONFIG_FILE_SIZE_BYTES:
        print(make_res("fail", "E_CONFIG_TOO_LARGE", f"Backup config file size ({file_size} bytes) exceeds limit ({MAX_CONFIG_FILE_SIZE_BYTES} bytes)"))
        sys.exit(0)

    errors = []
    warnings = []
    backup_keys = set()
    backup_entries = {}

    with open(backup_csv, 'r', encoding='utf-8-sig', errors='replace') as f:
        lines = f.readlines()

    if len(lines) > MAX_CONFIG_ROWS:
        print(make_res("fail", "E_CONFIG_ROW_LIMIT", f"Backup config exceeds max rows {MAX_CONFIG_ROWS}"))
        sys.exit(0)

    for line_num, line in enumerate(lines, 1):
        if len(line) > MAX_CONFIG_LINE_LENGTH:
            errors.append({"line": line_num, "code": "E_CONFIG_LINE_TOO_LONG", "msg": f"Line {line_num} exceeds {MAX_CONFIG_LINE_LENGTH} limit"})
            continue

        raw_line = line.strip().replace('\r', '')
        if not raw_line or raw_line.startswith('#'):
            continue

        parts = [p.strip() for p in raw_line.split('|')]
        dest = parts[0]
        if not dest.startswith("$MODELS/"):
            errors.append({"line": line_num, "code": "E_INVALID_DESTINATION_PREFIX", "msg": f"Backup line {line_num} key must start with $MODELS/"})
        elif '..' in dest or any(c in dest for c in [';', '&', '`', '$(']):
            errors.append({"line": line_num, "code": "E_PATH_TRAVERSAL", "msg": f"Backup line {line_num} traversal in key"})
        else:
            if models_base:
                resolved_dest = dest.replace('$MODELS', models_base)
                try:
                    b_real, c_dest = resolve_canonical_path(models_base, resolved_dest)
                    common = os.path.commonpath([b_real, c_dest])
                    if common != b_real:
                        errors.append({"line": line_num, "code": "E_PATH_OUTSIDE_MODELS", "msg": f"Backup line {line_num} destination escapes MODELS boundary via traversal or symlink"})
                except Exception as e:
                    errors.append({"line": line_num, "code": "E_PATH_TRAVERSAL", "msg": f"Backup line {line_num} path resolution error: {str(e)}"})

        if dest in backup_keys:
            errors.append({"line": line_num, "code": "E_DUPLICATE_MODEL_KEY", "msg": f"Backup line {line_num} duplicate key '{dest}'"})
        backup_keys.add(dest)

        alts = []
        for alt_url in parts[1:]:
            alt_url = alt_url.strip()
            if not alt_url:
                continue
            # Validate every mirror URL using unified helper
            m_ok, m_code, m_msg, m_data = validate_url_value(alt_url, allowed_schemes=('http', 'https'))
            if not m_ok:
                errors.append({"line": line_num, "code": m_code, "msg": f"Backup line {line_num} mirror URL error: {m_msg}"})
            else:
                alts.append(alt_url)
        backup_entries[dest] = alts

    # Check key set equality with primary CSV if provided
    if primary_csv and os.path.exists(primary_csv):
        primary_keys = set()
        with open(primary_csv, 'r', encoding='utf-8-sig', errors='replace') as pf:
            for pline in pf:
                pline = pline.strip().replace('\r', '')
                if not pline or pline.startswith('#'):
                    continue
                pparts = [p.strip() for p in pline.split('|')]
                if len(pparts) >= 2:
                    primary_keys.add(pparts[1])

        if primary_keys != backup_keys:
            missing = primary_keys - backup_keys
            extra = backup_keys - primary_keys
            if missing:
                errors.append({"code": "E_BACKUP_KEY_MISMATCH", "msg": f"Backup CSV is missing keys present in primary CSV: {list(missing)[:3]}"})
            if extra:
                errors.append({"code": "E_BACKUP_KEY_MISMATCH", "msg": f"Backup CSV has extra keys not in primary CSV: {list(extra)[:3]}"})

    status = "pass" if not errors else "fail"
    print(json.dumps({"status": status, "errors": errors, "warnings": warnings, "data": {"count": len(backup_keys), "keys": sorted(list(backup_keys)), "entries": backup_entries}}))
    sys.exit(0)

# ── 9. Nodes List Validation (HTTPS ONLY) ────────────────────────────────────
elif op == "validate_nodes_config":
    nodes_txt = args[0] if len(args) > 0 else ""
    nodes_base = args[1] if len(args) > 1 else ""

    if not os.path.exists(nodes_txt):
        print(make_res("fail", "E_CONFIG_MISSING", f"Nodes config not found: {nodes_txt}"))
        sys.exit(0)

    file_size = os.path.getsize(nodes_txt)
    if file_size > MAX_CONFIG_FILE_SIZE_BYTES:
        print(make_res("fail", "E_CONFIG_TOO_LARGE", f"Nodes config file size ({file_size} bytes) exceeds limit ({MAX_CONFIG_FILE_SIZE_BYTES} bytes)"))
        sys.exit(0)

    errors = []
    warnings = []
    entries = []
    seen_destinations = set()

    with open(nodes_txt, 'r', encoding='utf-8-sig', errors='replace') as f:
        lines = f.readlines()

    if len(lines) > MAX_CONFIG_ROWS:
        print(make_res("fail", "E_CONFIG_ROW_LIMIT", f"Nodes config exceeds max rows {MAX_CONFIG_ROWS}"))
        sys.exit(0)

    for line_num, line in enumerate(lines, 1):
        if len(line) > MAX_CONFIG_LINE_LENGTH:
            errors.append({"line": line_num, "code": "E_CONFIG_LINE_TOO_LONG", "msg": f"Node line {line_num} exceeds {MAX_CONFIG_LINE_LENGTH} limit"})
            continue

        raw_line = line.strip().replace('\r', '')
        if not raw_line or raw_line.startswith('#'):
            continue

        parts = [p.strip() for p in raw_line.split('|')]
        url = parts[0]
        dest = parts[1] if len(parts) > 1 else ""
        desc = parts[2] if len(parts) > 2 else ""

        # Validate git URL — MUST BE HTTPS ONLY
        u_ok, u_code, u_msg, u_data = validate_url_value(url, allowed_schemes=('https',))
        if not u_ok:
            errors.append({"line": line_num, "code": u_code, "msg": f"Node line {line_num} git URL error: {u_msg}"})

        # Validate destination
        if dest:
            if not dest.startswith("$CUSTOM_NODES/"):
                errors.append({"line": line_num, "code": "E_INVALID_DESTINATION_PREFIX", "msg": f"Node line {line_num} destination must start with $CUSTOM_NODES/"})
            elif '..' in dest or any(c in dest for c in [';', '&', '`', '$(']):
                errors.append({"line": line_num, "code": "E_PATH_TRAVERSAL", "msg": f"Node line {line_num} traversal in destination"})
            else:
                if nodes_base:
                    resolved_dest = dest.replace('$CUSTOM_NODES', nodes_base)
                    try:
                        b_real, c_dest = resolve_canonical_path(nodes_base, resolved_dest)
                        common = os.path.commonpath([b_real, c_dest])
                        if common != b_real:
                            errors.append({"line": line_num, "code": "E_PATH_OUTSIDE_NODES", "msg": f"Node line {line_num} escapes CUSTOM_NODES boundary via traversal or symlink"})
                    except Exception as e:
                        errors.append({"line": line_num, "code": "E_PATH_TRAVERSAL", "msg": f"Node line {line_num} path resolution error: {str(e)}"})

            if dest in seen_destinations:
                errors.append({"line": line_num, "code": "E_DUPLICATE_NODE_KEY", "msg": f"Node line {line_num} duplicate destination '{dest}'"})
            seen_destinations.add(dest)

        entries.append({"url": url, "destination": dest, "description": sanitize_str(desc)})

    status = "pass" if not errors else "fail"
    print(json.dumps({"status": status, "errors": errors, "warnings": warnings, "data": {"count": len(entries), "entries": entries}}))
    sys.exit(0)

else:
    print(make_res("fail", "E_UNKNOWN_OP", f"Unknown validation operation '{op}'"))
    sys.exit(1)
PY_VAL
}

# ================================================================================================================================
# 2. SHELL WRAPPER HELPERS (EXPOSED FOR PRODUCTION & TESTS)
# ================================================================================================================================

validate_safe_path() {
    local path="${1:-}"
    local res
    res=$(_py_validate_call "validate_safe_path" "$path")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

validate_model_destination() {
    local path="${1:-}"
    local models_root="${2:-${MODELS:-}}"
    local res
    res=$(_py_validate_call "validate_containment" "$models_root" "$path" "MODELS")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

validate_node_destination() {
    local path="${1:-}"
    local nodes_root="${2:-${CUSTOM_NODES:-}}"
    local res
    res=$(_py_validate_call "validate_containment" "$nodes_root" "$path" "NODES")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

validate_url() {
    local url="${1:-}"
    local allowed_schemes="${2:-http,https}"
    local res
    res=$(_py_validate_call "validate_url" "$url" "$allowed_schemes")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

classify_source_trust() {
    local url="${1:-}"
    local res
    res=$(_py_validate_call "validate_url" "$url" "http,https")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        echo "$res" | grep -oP '"trust_class":\s*"\K[^"]+' || echo "UNKNOWN"
    else
        echo "FORBIDDEN"
    fi
}

validate_sha256() {
    local sha="${1:-}"
    local res
    res=$(_py_validate_call "validate_sha256" "$sha")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

validate_numeric_config() {
    local name="${1:-CONFIG}"
    local val="${2:-}"
    local min_v="${3:-0}"
    local max_v="${4:-999999}"

    local res
    res=$(_py_validate_call "validate_numeric" "$name" "$val" "$min_v" "$max_v")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

validate_user_agent() {
    local ua="${1:-}"
    local res
    res=$(_py_validate_call "validate_user_agent" "$ua")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        local err_code err_msg
        err_code=$(echo "$res" | grep -oP '"error_code":\s*"\K[^"]+')
        err_msg=$(echo "$res" | grep -oP '"error_msg":\s*"\K[^"]+')
        echo -e "${RED}❌ [VALIDATION: $err_code] $err_msg${NC}" >&2
        return 1
    fi
}

validate_token_input() {
    local raw_tok="${1:-}"
    local res
    res=$(_py_validate_call "validate_token" "$raw_tok")
    local t_stat
    t_stat=$(echo "$res" | grep -oP '"token_status":\s*"\K[^"]+' | head -n1)
    if [ -n "$t_stat" ]; then
        echo "$t_stat"
        if [ "$t_stat" = "TOKEN_PRESENT" ] || [ "$t_stat" = "TOKEN_EMPTY" ]; then
            return 0
        fi
        return 1
    fi
    echo "TOKEN_INVALID_FORMAT"
    return 1
}

validate_models_config() {
    local csv_path="${1:-}"
    local models_root="${2:-${MODELS:-}}"
    local res
    res=$(_py_validate_call "validate_models_config" "$csv_path" "$models_root")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        return 1
    fi
}

validate_backup_config() {
    local backup_csv="${1:-}"
    local primary_csv="${2:-}"
    local models_root="${3:-${MODELS:-}}"
    local res
    res=$(_py_validate_call "validate_backup_config" "$backup_csv" "$primary_csv" "$models_root")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        return 1
    fi
}

validate_nodes_config() {
    local nodes_txt="${1:-}"
    local nodes_root="${2:-${CUSTOM_NODES:-}}"
    local res
    res=$(_py_validate_call "validate_nodes_config" "$nodes_txt" "$nodes_root")
    local status
    status=$(echo "$res" | grep -oP '"status":\s*"\K[^"]+')
    if [ "$status" = "pass" ]; then
        return 0
    else
        return 1
    fi
}

# ================================================================================================================================
# 3. COMPLETE PREFLIGHT SAFETY GATE ENGINE
# ================================================================================================================================

run_preflight() {
    local mode="${1:-full}" # full | models | nodes | validate_only
    local is_validate_only="${2:-0}"
    local script_root="${SCRIPT_DIR:-$(pwd)}"

    local primary_csv="$script_root/config/models_list.csv"
    local backup_csv="$script_root/config/models_backup_list.csv"
    local nodes_txt="$script_root/config/nodes_list.txt"

    local total_errors=0
    local total_warnings=0
    local err_messages=()
    local warn_messages=()

    local check_env="PASS"
    local check_python="PASS"
    local check_downloader="PASS"
    local check_prim_csv="PASS"
    local check_backup_csv="PASS"
    local check_key_eq="PASS"
    local check_nodes="PASS"
    local check_paths="PASS"
    local check_numeric="PASS"
    local check_disk="PASS"
    local check_token="OPTIONAL"

    # ── 1. Numeric Environment Configuration Check ───────────────────────────
    if ! validate_numeric_config "MAX_RETRIES" "${MAX_RETRIES:-5}" 1 20 >/dev/null 2>&1; then
        check_numeric="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("MAX_RETRIES must be between 1 and 20 (got: '${MAX_RETRIES:-}')")
    fi
    if ! validate_numeric_config "TIMEOUT" "${TIMEOUT:-60}" 5 3600 >/dev/null 2>&1; then
        check_numeric="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("TIMEOUT must be between 5 and 3600 seconds (got: '${TIMEOUT:-}')")
    fi
    if ! validate_numeric_config "REQUIRED_SPACE_GB" "${REQUIRED_SPACE_GB:-10}" 0 100000 >/dev/null 2>&1; then
        check_numeric="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("REQUIRED_SPACE_GB must be between 0 and 100000 (got: '${REQUIRED_SPACE_GB:-}')")
    fi
    if ! validate_numeric_config "ARIA2_CONNECTIONS_MAX" "${ARIA2_CONNECTIONS_MAX:-8}" 1 16 >/dev/null 2>&1; then
        check_numeric="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("ARIA2_CONNECTIONS_MAX must be between 1 and 16 (got: '${ARIA2_CONNECTIONS_MAX:-}')")
    fi
    if ! validate_user_agent "${USER_AGENT:-Mozilla/5.0}" >/dev/null 2>&1; then
        check_numeric="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("USER_AGENT contains invalid newline or control injection characters")
    fi

    # ── 2. Environment & Python Runtime Check ────────────────────────────────
    if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
        check_python="FAIL"; check_env="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("Python runtime not found on system")
    fi

    local has_dl=0
    command -v curl &>/dev/null && has_dl=1
    command -v wget &>/dev/null && has_dl=1
    command -v aria2c &>/dev/null && has_dl=1
    command -v python3 &>/dev/null && has_dl=1

    if [ $has_dl -eq 0 ]; then
        check_downloader="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("No download tool found (missing curl, wget, aria2c, python3)")
    fi

    # ── 3. Token Sanity Check ────────────────────────────────────────────────
    if [ -n "${CIVITAI_TOKEN:-}" ]; then
        local tok_status
        tok_status=$(validate_token_input "$CIVITAI_TOKEN")
        if [ "$tok_status" = "TOKEN_PRESENT" ]; then
            check_token="PRESENT"
        else
            check_token="INVALID"
            total_errors=$((total_errors + 1))
            err_messages+=("Civitai API token contains illegal whitespace or control characters")
        fi
    fi

    # ── 4. Models Config Validation (if mode is full or models) ───────────────
    if [ "$mode" = "full" ] || [ "$mode" = "models" ]; then
        if [ -f "$primary_csv" ]; then
            local p_res
            p_res=$(_py_validate_call "validate_models_config" "$primary_csv" "${MODELS:-}")
            local p_stat
            p_stat=$(echo "$p_res" | grep -oP '"status":\s*"\K[^"]+')
            if [ "$p_stat" != "pass" ]; then
                check_prim_csv="FAIL"; total_errors=$((total_errors + 1))
                while IFS= read -r emsg; do
                    [ -n "$emsg" ] && err_messages+=("Primary CSV: $emsg")
                done < <(echo "$p_res" | grep -oP '"msg":\s*"\K[^"]+')
            fi
        else
            check_prim_csv="FAIL"; total_errors=$((total_errors + 1))
            err_messages+=("Missing primary models config: $primary_csv")
        fi

        if [ -f "$backup_csv" ]; then
            local b_res
            b_res=$(_py_validate_call "validate_backup_config" "$backup_csv" "$primary_csv" "${MODELS:-}")
            local b_stat
            b_stat=$(echo "$b_res" | grep -oP '"status":\s*"\K[^"]+')
            if [ "$b_stat" != "pass" ]; then
                check_backup_csv="FAIL"; check_key_eq="FAIL"; total_errors=$((total_errors + 1))
                while IFS= read -r emsg; do
                    [ -n "$emsg" ] && err_messages+=("Backup CSV: $emsg")
                done < <(echo "$b_res" | grep -oP '"msg":\s*"\K[^"]+')
            fi
        else
            check_backup_csv="WARN"; total_warnings=$((total_warnings + 1))
            warn_messages+=("Backup models config not found: $backup_csv")
        fi
    fi

    # ── 5. Nodes Config Validation (if mode is full or nodes) ────────────────
    if [ "$mode" = "full" ] || [ "$mode" = "nodes" ]; then
        if [ -f "$nodes_txt" ]; then
            local n_res
            n_res=$(_py_validate_call "validate_nodes_config" "$nodes_txt" "${CUSTOM_NODES:-}")
            local n_stat
            n_stat=$(echo "$n_res" | grep -oP '"status":\s*"\K[^"]+')
            if [ "$n_stat" != "pass" ]; then
                check_nodes="FAIL"; total_errors=$((total_errors + 1))
                while IFS= read -r emsg; do
                    [ -n "$emsg" ] && err_messages+=("Nodes config: $emsg")
                done < <(echo "$n_res" | grep -oP '"msg":\s*"\K[^"]+')
            fi
        else
            check_nodes="FAIL"; total_errors=$((total_errors + 1))
            err_messages+=("Missing custom nodes config: $nodes_txt")
        fi
    fi

    # ── 6. Disk Space Check ──────────────────────────────────────────────────
    local target_disk_check="${COMFY_BASE:-.}"
    local disk_avail_gb
    disk_avail_gb=$(df -P -BG "$target_disk_check" 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9' || echo "999")
    if [ -n "$disk_avail_gb" ] && [ "$disk_avail_gb" -lt "${REQUIRED_SPACE_GB:-10}" ] 2>/dev/null; then
        check_disk="FAIL"; total_errors=$((total_errors + 1))
        err_messages+=("Available disk space (${disk_avail_gb}GB) is less than required (${REQUIRED_SPACE_GB:-10}GB)")
    fi

    # ── Print Human-Readable Preflight Report ─────────────────────────────────
    echo -e "\n${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}║             🛡️  COMFYUI SETUP PRE-FLIGHT GATE              ║${NC}"
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    printf "  %-25s : " "Environment"
    [ "$check_env" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"
    printf "  %-25s : " "Python Runtime"
    [ "$check_python" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"
    printf "  %-25s : " "Downloader Engine"
    [ "$check_downloader" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"
    printf "  %-25s : " "Numeric Configurations"
    [ "$check_numeric" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"

    if [ "$mode" = "full" ] || [ "$mode" = "models" ]; then
        printf "  %-25s : " "Primary Models CSV"
        [ "$check_prim_csv" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"
        printf "  %-25s : " "Backup Models CSV"
        [ "$check_backup_csv" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${YELLOW}WARN${NC}"
        printf "  %-25s : " "Exact Key Set Equality"
        [ "$check_key_eq" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"
    fi

    if [ "$mode" = "full" ] || [ "$mode" = "nodes" ]; then
        printf "  %-25s : " "Custom Nodes Config"
        [ "$check_nodes" = "PASS" ] && echo -e "${GREEN}PASS${NC}" || echo -e "${RED}FAIL${NC}"
    fi

    printf "  %-25s : " "Civitai API Token"
    [ "$check_token" = "PRESENT" ] && echo -e "${GREEN}PRESENT${NC}" || echo -e "${YELLOW}OPTIONAL / NOT SET${NC}"
    printf "  %-25s : " "Disk Space Available"
    [ "$check_disk" = "PASS" ] && echo -e "${GREEN}PASS (${disk_avail_gb}GB free)${NC}" || echo -e "${RED}FAIL (${disk_avail_gb}GB free)${NC}"

    echo -e "${MAGENTA}──────────────────────────────────────────────────────────────${NC}"
    echo -e "  Warnings : ${YELLOW}${total_warnings}${NC}"
    echo -e "  Errors   : ${RED}${total_errors}${NC}"

    if [ $total_errors -gt 0 ]; then
        echo -e "\n${RED}❌ PREFLIGHT RESULT: BLOCKED${NC}"
        echo -e "${RED}Vui lòng khắc phục các lỗi sau trước khi tiếp tục:${NC}"
        for em in "${err_messages[@]}"; do
            echo -e "  ${RED}• [ERROR] $em${NC}"
        done
        echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}\n"
        return 1
    else
        echo -e "\n${GREEN}✅ PREFLIGHT RESULT: PASS${NC}"
        for wm in "${warn_messages[@]}"; do
            echo -e "  ${YELLOW}• [WARN] $wm${NC}"
        done
        echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}\n"
        return 0
    fi
}

export -f validate_safe_path validate_model_destination validate_node_destination validate_url classify_source_trust validate_sha256 validate_numeric_config validate_user_agent validate_token_input validate_models_config validate_backup_config validate_nodes_config run_preflight 2>/dev/null || true
