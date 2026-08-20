# Effective Model Fallback & Source Redundancy Coverage Matrix

> **Policy**: Third-party mirrors require authoritative SHA256 verification to be effectively enabled.

| # | Model Destination | Primary Source | Backup Sources | SHA256 Present | Effectively Usable Sources |
|---|---|---|---|---|---|
| 1 | `$MODELS/checkpoints/IL/oneObsession_v23.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, THIRD_PARTY_MIRROR` | ✅ YES | **3 sources** |
| 2 | `$MODELS/checkpoints/IL/illustriousXL20_v20.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, THIRD_PARTY_MIRROR` | ✅ YES | **3 sources** |
| 3 | `$MODELS/checkpoints/IL/ultimateHentaiAnimeRXTRexAnime_rxV1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 4 | `$MODELS/checkpoints/IL/waiIllustriousSDXL_v170.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 5 | `$MODELS/controlnet/controlnet_openpose_xl.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **4 sources** |
| 6 | `$MODELS/controlnet/illustriousXLCanny_v10.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 7 | `$MODELS/ipadapter/ip-adapter_sdxl_vit-h.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 8 | `$MODELS/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 9 | `$MODELS/clip_vision/dino_v3_vit_l.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 10 | `$MODELS/insightface/inswapper_128.onnx` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **4 sources** |
| 11 | `$MODELS/facerestore/codeformer-v0.1.0.pth` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, THIRD_PARTY_MIRROR, THIRD_PARTY_MIRROR` | ❌ NO | **2 sources** |
| 12 | `$MODELS/facexlib/detection_Resnet50_Final.pth` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, THIRD_PARTY_MIRROR` | ❌ NO | **1 sources** |
| 13 | `$MODELS/vae/ponyStandardVAE_v10.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 14 | `$MODELS/vae/trellis_2_shape_vae_bf16.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 15 | `$MODELS/vae/trellis_2_texture_vae_bf16.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 16 | `$MODELS/upscale_models/4xUltrasharp_4xUltrasharpV10.pt` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, THIRD_PARTY_MIRROR` | ✅ YES | **3 sources** |
| 17 | `$MODELS/upscale_models/4xFaceUpDAT.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 18 | `$MODELS/diffusion_models/trellis_2_bf16.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 19 | `$MODELS/loras/Quality/Add_more_details_pony.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 20 | `$MODELS/loras/Quality/add-detail-xl.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 21 | `$MODELS/loras/Quality/illustrious_masterpieces_v3.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 22 | `$MODELS/loras/Quality/AddMicroDetails_Illustrious_v6.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 23 | `$MODELS/loras/Face/bieu_cam-betterahegao.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 24 | `$MODELS/loras/Face/bieu_cam-toro_ahe_pony.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 25 | `$MODELS/loras/Hands/pony_good_hands.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 26 | `$MODELS/loras/Character/c1_fleurdelys_cartethyia_ilv1.0_xl-3ep.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 27 | `$MODELS/loras/Character/Chen_Qianyu_-_Arknights_Endfield_-_Illustrious.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 28 | `$MODELS/loras/Character/qingxiaoV1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 29 | `$MODELS/loras/Style/illmikoyan_style_v2_illustrious_epoch_7.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 30 | `$MODELS/loras/Style/ATRex_style-12V2Rev.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 31 | `$MODELS/loras/Style/Phong_Cach_HEN-GEN_illust_0.2v.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 32 | `$MODELS/loras/Style/Phong_Cach_HEN-CMN_Pony_0.1v.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 33 | `$MODELS/loras/Style/FComic_1to1000_Pony_V1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 34 | `$MODELS/loras/Style/FComic_1to1000_IL_V2.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 35 | `$MODELS/loras/Style/Phong_Cach-Anime_Style_1to1000_Pony_V1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 36 | `$MODELS/loras/Style/Phong_Cach-HPI2_Anime_IL_V1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 37 | `$MODELS/loras/Effect/da_bong+mo_hoi-V4_Glossy_Skin.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 38 | `$MODELS/loras/Effect/da_bong-shiny_wet_skin_v2.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 39 | `$MODELS/loras/Pose/NSFW-22-H-e8.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 40 | `$MODELS/loras/Pose/Midis_Defeat2_IL.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 41 | `$MODELS/loras/Pose/Fumihiko_Defeat_PONY.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ✅ YES | **3 sources** |
| 42 | `$MODELS/loras/Pose/phong_cach-hands-free_blowjob-IL.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY, OFFICIAL_FIRST_PARTY` | ❌ NO | **3 sources** |

## Summary Statistics

- **Total Models**: 42
- **Models with 1 usable source**: 1
- **Models with 2 usable sources**: 1
- **Models with 3+ usable sources**: 40
- **Models with no effective backup**: 1
- **SHA256 Coverage**: 39 / 42 (92.8%)
- **Third-Party URLs Configured**: 16
- **Third-Party URLs Effectively Enabled (with SHA)**: 16
- **Third-Party URLs Blocked (missing SHA)**: 0
