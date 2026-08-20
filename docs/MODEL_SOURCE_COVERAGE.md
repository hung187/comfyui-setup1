# Model Effective Fallback Coverage Matrix

Báo cáo phân tích số lượng nguồn khả dụng thực tế (**Effectively Usable Sources**) dựa trên chính sách Trust Tier và xác thực toàn vẹn SHA256.

## 1. Tổng Kết Thống Kê

- **Tổng số Models**: 42
- **Models có 1 nguồn khả dụng**: 1
- **Models có 2 nguồn khả dụng**: 8
- **Models có 3+ nguồn khả dụng**: 33
- **Models không có backup hiệu lực**: 1

### Độ Bao Phủ SHA256 & Third-Party Mirrors:
- **Số models có Authoritative SHA256**: 30 / 42
- **Số models chưa có Authoritative SHA256**: 12 / 42
- **Tổng số Third-Party Mirror URLs được cấu hình**: 16
- **Third-Party Mirrors được KÍCH HOẠT (vì có SHA256 đối soát)**: 3
- **Third-Party Mirrors bị CHẶN (do thiếu SHA256 theo chính sách bảo mật)**: 13

## 2. Ma Trận Chi Tiết Từng Model

| Model Destination | Primary Source | Backup 1 | Backup 2 | Backup 3 | SHA256? | Usable Sources |
|---|---|---|---|---|---|---|
| `$MODELS/checkpoints/IL/oneObsession_v23.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `NONE` | **YES** | **3** |
| `$MODELS/checkpoints/IL/illustriousXL20_v20.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `NONE` | **YES** | **3** |
| `$MODELS/checkpoints/IL/ultimateHentaiAnimeRXTRexAnime_rxV1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/checkpoints/IL/waiIllustriousSDXL_v170.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/controlnet/controlnet_openpose_xl.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | **NO** | **3** |
| `$MODELS/controlnet/illustriousXLCanny_v10.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/ipadapter/ip-adapter_sdxl_vit-h.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/clip_vision/dino_v3_vit_l.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/insightface/inswapper_128.onnx` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | **NO** | **3** |
| `$MODELS/facerestore/codeformer-v0.1.0.pth` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `THIRD_PARTY_MIRROR` | **NO** | **2** |
| `$MODELS/facexlib/detection_Resnet50_Final.pth` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `THIRD_PARTY_MIRROR` | `NONE` | **NO** | **1** |
| `$MODELS/vae/ponyStandardVAE_v10.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/vae/trellis_2_shape_vae_bf16.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/vae/trellis_2_texture_vae_bf16.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/upscale_models/4xUltrasharp_4xUltrasharpV10.pt` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `NONE` | **YES** | **3** |
| `$MODELS/upscale_models/4xFaceUpDAT.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/diffusion_models/trellis_2_bf16.safetensors` | `OFFICIAL_FIRST_PARTY` | `THIRD_PARTY_MIRROR` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **2** |
| `$MODELS/loras/Quality/Add_more_details_pony.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Quality/add-detail-xl.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Quality/illustrious_masterpieces_v3.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Quality/AddMicroDetails_Illustrious_v6.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Face/bieu_cam-betterahegao.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Face/bieu_cam-toro_ahe_pony.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Hands/pony_good_hands.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Character/c1_fleurdelys_cartethyia_ilv1.0_xl-3ep.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Character/Chen_Qianyu_-_Arknights_Endfield_-_Illustrious.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Character/qingxiaoV1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/illmikoyan_style_v2_illustrious_epoch_7.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/ATRex_style-12V2Rev.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/Phong_Cach_HEN-GEN_illust_0.2v.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/Phong_Cach_HEN-CMN_Pony_0.1v.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/FComic_1to1000_Pony_V1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/FComic_1to1000_IL_V2.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/Phong_Cach-Anime_Style_1to1000_Pony_V1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Style/Phong_Cach-HPI2_Anime_IL_V1.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Effect/da_bong+mo_hoi-V4_Glossy_Skin.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Effect/da_bong-shiny_wet_skin_v2.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Pose/NSFW-22-H-e8.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Pose/Midis_Defeat2_IL.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Pose/Fumihiko_Defeat_PONY.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **YES** | **3** |
| `$MODELS/loras/Pose/phong_cach-hands-free_blowjob-IL.safetensors` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `OFFICIAL_FIRST_PARTY` | `NONE` | **NO** | **3** |
