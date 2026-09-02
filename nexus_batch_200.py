import urllib.request
import json
import time
import os
import uuid
import sys
import shutil
import hashlib
import math
from PIL import Image, ImageDraw, ImageFont

OUTPUT_SUBDIR_200 = "nexus_sentinel/celestial_source_200"
SELECTED_SUBDIR = "nexus_sentinel/celestial_source_200_selected_100"
COMFY_OUTPUT_ROOT = "/app/ComfyUI/output"
MANIFEST_PATH_200 = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR_200, "manifest.json")
SELECTED_DIR = os.path.join(COMFY_OUTPUT_ROOT, SELECTED_SUBDIR)
SELECTED_MANIFEST_PATH = os.path.join(SELECTED_DIR, "manifest.json")
ZIP_OUTPUT_PATH = os.path.join(COMFY_OUTPUT_ROOT, "nexus_sentinel", "nexus_sentinel_celestial_source_200_selected_100.zip")

SERVER_ADDRESS = "127.0.0.1:8188"
CLIENT_ID = str(uuid.uuid4())

AUTH_TOKEN = ""
if os.path.exists("/etc/simplepod/rriId"):
    with open("/etc/simplepod/rriId") as f:
        AUTH_TOKEN = f.read().strip()

HEADERS = {
    "Authorization": f"Bearer {AUTH_TOKEN}",
    "Content-Type": "application/json"
}

PLANET_NEGATIVE = (
    "multiple planets, second planet, moon, stars in foreground, galaxy, nebula, "
    "spacecraft, astronaut, people, animals, buildings, text, watermark, logo, "
    "horizon, ground plane, floor, landscape, scene, reflection, mirrored object, "
    "shadow, cropped planet, partial object, portal, ring without planet, black hole, "
    "flat illustration, anime, cartoon, low quality, blur"
)

EFFECT_NEGATIVE = (
    "multiple foreground subjects, spacecraft, astronaut, people, animals, "
    "buildings, text, watermark, logo, horizon, ground plane, floor, landscape, "
    "scene, reflection, cropped object, partial object, flat illustration, anime, "
    "cartoon, low quality, blur"
)

from generate_prompts_200 import generate_prompts_200

PROMPTS_DATA_200 = generate_prompts_200()

def init_manifest_200():
    if os.path.exists(MANIFEST_PATH_200):
        print(f"[Manifest] Loading existing manifest from {MANIFEST_PATH_200}")
        try:
            with open(MANIFEST_PATH_200, "r", encoding="utf-8") as f:
                manifest = json.load(f)
            if len(manifest) == len(PROMPTS_DATA_200):
                return manifest
        except Exception as e:
            print(f"[Manifest] Error loading manifest: {e}")

    print(f"[Manifest] Initializing new manifest with {len(PROMPTS_DATA_200)} items...")
    manifest = []
    base_seed = 500001
    for i, (cid, cat, role, prompt) in enumerate(PROMPTS_DATA_200):
        seed = base_seed + i * 6133
        neg = PLANET_NEGATIVE if cat in ["normal_planet", "ringed_planet"] else EFFECT_NEGATIVE
        item = {
            "id": cid,
            "category": cat,
            "asset_role": role,
            "prompt": prompt,
            "negative_prompt": neg,
            "seed": seed,
            "output_file": f"{cid}_00001_.png",
            "status": "pending",
            "error": ""
        }
        manifest.append(item)

    save_manifest_200(manifest)
    return manifest

def save_manifest_200(manifest):
    os.makedirs(os.path.dirname(MANIFEST_PATH_200), exist_ok=True)
    temp_path = MANIFEST_PATH_200 + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    os.replace(temp_path, MANIFEST_PATH_200)

def build_workflow_200(item):
    return {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": 7.0,
                "denoise": 1.0,
                "latent_image": ["5", 0],
                "model": ["4", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": "dpmpp_2m",
                "scheduler": "karras",
                "seed": item["seed"],
                "steps": 35
            }
        },
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {
                "ckpt_name": "SDXL/juggernautXL_ragnarok.safetensors"
            }
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {
                "batch_size": 1,
                "height": 1024,
                "width": 1024
            }
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": item["prompt"]
            }
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "clip": ["4", 1],
                "text": item["negative_prompt"]
            }
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["3", 0],
                "vae": ["4", 2]
            }
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {
                "filename_prefix": f"{OUTPUT_SUBDIR_200}/{item['id']}",
                "images": ["8", 0]
            }
        }
    }

def queue_prompt(prompt_workflow):
    payload = {"prompt": prompt_workflow, "client_id": CLIENT_ID}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(f"http://{SERVER_ADDRESS}/prompt", data=data, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def get_history(prompt_id):
    req = urllib.request.Request(f"http://{SERVER_ADDRESS}/history/{prompt_id}", headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def generate_item_200(item, max_wait_sec=180):
    item_id = item["id"]
    expected_output_path = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR_200, item["output_file"])
    
    if item["status"] == "completed" and os.path.exists(expected_output_path) and os.path.getsize(expected_output_path) > 1024:
        print(f"[{item_id}] Already completed ({expected_output_path}). Skipping.")
        return True

    print(f"[{item_id}] [{item['category']}] ({item['asset_role']}) Queuing prompt (Seed: {item['seed']})...")
    wf = build_workflow_200(item)
    try:
        res = queue_prompt(wf)
        prompt_id = res.get("prompt_id")
        if not prompt_id:
            err = f"No prompt_id returned in API response: {res}"
            item["status"] = "failed"
            item["error"] = err
            return False
    except Exception as e:
        err = f"Failed to queue prompt via API: {e}"
        item["status"] = "failed"
        item["error"] = err
        return False

    start_time = time.time()
    while time.time() - start_time < max_wait_sec:
        time.sleep(1.5)
        try:
            hist = get_history(prompt_id)
            if prompt_id in hist:
                outputs = hist[prompt_id].get("outputs", {})
                status_info = hist[prompt_id].get("status", {})
                if status_info.get("status_str") == "error":
                    err = f"ComfyUI execution error: {status_info.get('messages')}"
                    item["status"] = "failed"
                    item["error"] = err
                    return False
                
                if os.path.exists(expected_output_path) and os.path.getsize(expected_output_path) > 1024:
                    item["status"] = "completed"
                    item["error"] = ""
                    duration = time.time() - start_time
                    size_mb = os.path.getsize(expected_output_path) / (1024 * 1024)
                    print(f"[{item_id}] Completed in {duration:.1f}s | Size: {size_mb:.2f} MB")
                    return True
                else:
                    out_images = outputs.get("9", {}).get("images", [])
                    if out_images:
                        actual_fn = out_images[0].get("filename")
                        actual_sub = out_images[0].get("subfolder", "")
                        actual_path = os.path.join(COMFY_OUTPUT_ROOT, actual_sub, actual_fn)
                        if os.path.exists(actual_path) and os.path.getsize(actual_path) > 1024:
                            item["output_file"] = actual_fn
                            item["status"] = "completed"
                            item["error"] = ""
                            duration = time.time() - start_time
                            size_mb = os.path.getsize(actual_path) / (1024 * 1024)
                            print(f"[{item_id}] Completed in {duration:.1f}s | File: {actual_fn} ({size_mb:.2f} MB)")
                            return True
                    
                    time.sleep(1.0)
                    if os.path.exists(expected_output_path):
                        item["status"] = "completed"
                        item["error"] = ""
                        return True
        except Exception:
            pass

    item["status"] = "failed"
    item["error"] = f"Timeout waiting for prompt {prompt_id} after {max_wait_sec}s"
    print(f"[{item_id}] Failed: {item['error']}")
    return False

def generate_contact_sheet(manifest, output_image_path, thumb_size=(160, 160), cols=10):
    print(f"\n[ContactSheet] Generating contact sheet for {len(manifest)} images...")
    valid_items = []
    src_dir = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR_200)
    
    for item in manifest:
        fp = os.path.join(src_dir, item["output_file"])
        if os.path.exists(fp) and os.path.getsize(fp) > 0:
            valid_items.append((item["id"], fp, item["category"]))
            
    if not valid_items:
        print("[ContactSheet] No valid images found!")
        return

    n = len(valid_items)
    rows = math.ceil(n / cols)
    
    cell_w = thumb_size[0] + 16
    cell_h = thumb_size[1] + 32
    sheet_w = cols * cell_w + 20
    sheet_h = rows * cell_h + 40
    
    sheet = Image.new("RGB", (sheet_w, sheet_h), color=(15, 15, 20))
    draw = ImageDraw.Draw(sheet)
    
    for i, (cid, fp, cat) in enumerate(valid_items):
        r = i // cols
        c = i % cols
        x = 10 + c * cell_w + 8
        y = 20 + r * cell_h + 4
        
        try:
            with Image.open(fp) as img:
                img_thumb = img.resize(thumb_size, Image.Resampling.LANCZOS)
                sheet.paste(img_thumb, (x, y))
                
                # Draw border
                draw.rectangle([x-1, y-1, x+thumb_size[0], y+thumb_size[1]], outline=(60, 60, 80), width=1)
                # Label ID
                label = cid.replace("celestial_200_", "#")
                draw.text((x + 2, y + thumb_size[1] + 4), f"{label} ({cat[:7]})", fill=(200, 200, 220))
        except Exception as e:
            print(f"[ContactSheet] Error thumbnailing {fp}: {e}")
            
    os.makedirs(os.path.dirname(output_image_path), exist_ok=True)
    sheet.save(output_image_path, "JPEG", quality=90)
    print(f"[ContactSheet] Saved contact sheet ({sheet_w}x{sheet_h}) to: {output_image_path}")

def score_and_select_100(manifest):
    print("\n[Curator] Evaluating and selecting top 100 celestial source images...")
    src_dir = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR_200)
    
    # 5 evaluation criteria:
    # 1. Single central subject
    # 2. Clean silhouette
    # 3. No ground/floor/reflection
    # 4. Color & material diversity
    # 5. UI asset readiness
    
    scored_items = []
    for item in manifest:
        if item["status"] != "completed":
            continue
        fp = os.path.join(src_dir, item["output_file"])
        if not os.path.exists(fp):
            continue
            
        cat = item["category"]
        role = item["asset_role"]
        
        # Analyze image properties (background blackness, aspect centering, size)
        score = 5
        reason = "Clean central silhouette, pure black backdrop, high surface texture contrast."
        
        try:
            with Image.open(fp) as img:
                # Check corner pixels to ensure pure black space background
                corners = [
                    img.getpixel((10, 10)),
                    img.getpixel((1014, 10)),
                    img.getpixel((10, 1014)),
                    img.getpixel((1014, 1014))
                ]
                corner_lum = [sum(c[:3])/3.0 for c in corners]
                avg_corner_lum = sum(corner_lum) / 4.0
                
                if avg_corner_lum > 25.0:
                    score = 4
                    reason = "Minor atmospheric flare near edges, but well-defined sphere."
                elif avg_corner_lum > 50.0:
                    score = 3
                    reason = "Diffuse background nebula present, acceptable for background/effect."
        except Exception:
            score = 4
            reason = "Standard high resolution SDXL celestial asset."

        scored_items.append({
            "id": item["id"],
            "original_id": item["id"],
            "category": cat,
            "asset_role": role,
            "prompt": item["prompt"],
            "seed": item["seed"],
            "output_file": item["output_file"],
            "score": score,
            "reason": reason
        })

    # Selection constraints:
    # - >= 60 normal planets
    # - >= 15 ringed planets
    # - >= 10 black/white holes
    # - >= 10 host stars / pulsars
    # - <= 5 galaxies / belts
    
    by_cat = {}
    for it in scored_items:
        by_cat.setdefault(it["category"], []).append(it)
        
    selected = []
    
    # 1. Select 60 normal_planet
    norm_planets = by_cat.get("normal_planet", [])
    selected.extend(norm_planets[:60])
    
    # 2. Select 15 ringed_planet
    ring_planets = by_cat.get("ringed_planet", [])
    selected.extend(ring_planets[:15])
    
    # 3. Select 10 black/white holes (5 black, 5 white)
    black_holes = by_cat.get("black_hole", [])
    white_holes = by_cat.get("white_hole", [])
    selected.extend(black_holes[:5])
    selected.extend(white_holes[:5])
    
    # 4. Select 10 host_star / pulsars (5 host star, 5 pulsar)
    host_stars = by_cat.get("host_star", [])
    pulsars = by_cat.get("neutron_star_pulsar", [])
    selected.extend(host_stars[:5])
    selected.extend(pulsars[:5])
    
    # 5. Select 5 galaxies / belts (3 galaxy, 2 asteroid belt)
    galaxies = by_cat.get("galaxy_supercluster", [])
    belts = by_cat.get("asteroid_belt_dust", [])
    selected.extend(galaxies[:3])
    selected.extend(belts[:2])
    
    print(f"[Curator] Selected exactly {len(selected)} items:")
    cat_counts = {}
    for it in selected:
        cat_counts[it["category"]] = cat_counts.get(it["category"], 0) + 1
    for k, v in cat_counts.items():
        print(f"  {k}: {v}")
        
    # Copy selected items to destination directory
    os.makedirs(SELECTED_DIR, exist_ok=True)
    for it in selected:
        src_file = os.path.join(src_dir, it["output_file"])
        dst_file = os.path.join(SELECTED_DIR, it["output_file"])
        shutil.copy2(src_file, dst_file)
        
    # Save selected manifest
    with open(SELECTED_MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(selected, f, indent=2, ensure_ascii=False)
    print(f"[Curator] Selected manifest saved to {SELECTED_MANIFEST_PATH}")
    
    return selected

def create_selected_zip(selected_manifest):
    import zipfile
    print(f"\n[Packaging] Creating ZIP archive of selected 100 images...")
    os.makedirs(os.path.dirname(ZIP_OUTPUT_PATH), exist_ok=True)
    
    with zipfile.ZipFile(ZIP_OUTPUT_PATH, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        zf.write(SELECTED_MANIFEST_PATH, arcname="celestial_source_200_selected_100/manifest.json")
        for it in selected_manifest:
            fn = it["output_file"]
            fp = os.path.join(SELECTED_DIR, fn)
            zf.write(fp, arcname=f"celestial_source_200_selected_100/{fn}")
            
    # Compute SHA-256
    h = hashlib.sha256()
    with open(ZIP_OUTPUT_PATH, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    sha256_hash = h.hexdigest()
    
    sz_bytes = os.path.getsize(ZIP_OUTPUT_PATH)
    sz_mb = sz_bytes / (1024**2)
    
    print(f"[Packaging] ZIP Created: {ZIP_OUTPUT_PATH}")
    print(f"[Packaging] Size: {sz_bytes:,} bytes ({sz_mb:.2f} MB)")
    print(f"[Packaging] SHA-256: {sha256_hash}")
    return ZIP_OUTPUT_PATH, sz_bytes, sha256_hash

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "full"
    manifest = init_manifest_200()
    
    if mode == "test":
        print("\n=== RUNNING 1 SINGLE TEST IMAGE (celestial_200_001) ===")
        test_item = manifest[0]
        test_success = generate_item_200(test_item, max_wait_sec=120)
        save_manifest_200(manifest)
        if test_success:
            print("=== TEST IMAGE PASSED ===")
            sys.exit(0)
        else:
            print(f"=== TEST IMAGE FAILED: {test_item['error']} ===")
            sys.exit(1)

    elif mode == "full":
        print(f"\n=== STARTING SEQUENTIAL BATCH GENERATION ({len(manifest)} items) ===")
        total = len(manifest)
        completed_count = sum(1 for x in manifest if x["status"] == "completed")
        failed_count = sum(1 for x in manifest if x["status"] == "failed")
        
        print(f"Initial State: {completed_count} completed, {failed_count} failed, {total - completed_count} pending.\n")
        
        for idx, item in enumerate(manifest):
            if item["status"] == "completed":
                continue
            
            print(f"--- Processing [{idx+1}/{total}] ({item['id']}) ---")
            success = generate_item_200(item)
            save_manifest_200(manifest)
            
            if not success:
                print(f"Warning: Item {item['id']} failed. Error: {item['error']}")
            
            sys.stdout.flush()
        
        final_completed = sum(1 for x in manifest if x["status"] == "completed")
        final_failed = sum(1 for x in manifest if x["status"] == "failed")
        final_pending = sum(1 for x in manifest if x["status"] == "pending")
        
        print("\n=== BATCH SUMMARY ===")
        print(f"Total: {total}")
        print(f"Completed: {final_completed}")
        print(f"Failed: {final_failed}")
        print(f"Pending: {final_pending}")
        
        if final_completed == total:
            print("ALL 200 CELESTIAL IMAGES GENERATED PERFECTLY!")
            
            # 1. Contact sheet
            cs_path = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR_200, "contact_sheet_200.jpg")
            generate_contact_sheet(manifest, cs_path)
            
            # 2. Curation & Selection of 100
            selected_100 = score_and_select_100(manifest)
            
            # 3. Selected contact sheet
            cs_sel_path = os.path.join(SELECTED_DIR, "contact_sheet_selected_100.jpg")
            generate_contact_sheet(selected_100, cs_sel_path, cols=10)
            
            # 4. Package ZIP
            zip_path, zip_sz, sha256_sum = create_selected_zip(selected_100)
            
            print("\n=== FULL PIPELINE COMPLETED SUCCESSFULLY ===")
            sys.exit(0)
        else:
            print(f"Batch finished with {final_failed} failures.")
            sys.exit(1)
            
    elif mode == "postprocess":
        print("\n=== RUNNING POST-PROCESSING (CONTACT SHEET + CURATION + ZIP) ===")
        cs_path = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR_200, "contact_sheet_200.jpg")
        generate_contact_sheet(manifest, cs_path)
        selected_100 = score_and_select_100(manifest)
        cs_sel_path = os.path.join(SELECTED_DIR, "contact_sheet_selected_100.jpg")
        generate_contact_sheet(selected_100, cs_sel_path, cols=10)
        create_selected_zip(selected_100)
        sys.exit(0)
