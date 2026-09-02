import urllib.request
import json
import time
import os
import uuid
import sys

OUTPUT_SUBDIR = "nexus_sentinel/celestial_source_100"
COMFY_OUTPUT_ROOT = "/app/ComfyUI/output"
MANIFEST_PATH = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR, "manifest.json")
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

COMMON_NEGATIVE = (
    "multiple foreground objects, second planet, moon, spacecraft, astronaut, "
    "buildings, people, animals, text, watermark, logo, horizon, ground plane, "
    "landscape, cropped object, partial object, blur, low quality, cartoon, anime"
)

# 100 Defined Celestial Prompts
PROMPTS_DATA = [
    # --- 42 Normal Planets (mesh_candidate) ---
    ("celestial_001", "normal_planet", "mesh_candidate",
     "a photorealistic super-earth terrestrial planet, vibrant azure oceans, emerald green continents, swirling white storm cloud patterns, centered single celestial sphere, isolated on pure deep black space background, subtle atmospheric rim glow, 8k resolution, cinematic space photography"),
    ("celestial_002", "normal_planet", "mesh_candidate",
     "a glowing magma volcanic planet with incandescent lava rivers, fractured dark basalt tectonic plates, active glowing calderas, centered single celestial sphere, isolated on pure deep black space background, subtle smoky heat haze, 8k resolution, photorealistic astronomy"),
    ("celestial_003", "normal_planet", "mesh_candidate",
     "a frozen ice giant cryo-world, translucent turquoise glacial sheets, deep nitrogen frost fissures, delicate pale cyan vapor haze, centered single celestial sphere, isolated on pure deep black space background, 8k resolution, crisp crystalline detail"),
    ("celestial_004", "normal_planet", "mesh_candidate",
     "an arid desert rocky planet, vast terracotta canyons, golden sand dune oceans, dusty ochre atmospheric limb, centered single celestial sphere, isolated on pure deep black space background, 8k resolution, photorealistic"),
    ("celestial_005", "normal_planet", "mesh_candidate",
     "a toxic greenhouse planet, dense swirling sulphuric acid yellow-green cloud bands, violet lightning flashes across the upper atmosphere, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_006", "normal_planet", "mesh_candidate",
     "a deep ocean water world completely covered by a global cobalt-blue ocean, dynamic white cyclonic typhoon vortices, centered single celestial sphere, isolated on pure deep black space background, subtle sun glint reflection, 8k resolution"),
    ("celestial_007", "normal_planet", "mesh_candidate",
     "a metallic iron-rich terrestrial world, reflective gunmetal gray mineral crust, polished asteroid impact craters, sharp specular highlights, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_008", "normal_planet", "mesh_candidate",
     "a stark cratered barren planet, slate-gray lunar regolith surface, deep ancient impact basins, bright crater ray systems, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_009", "normal_planet", "mesh_candidate",
     "a turbulent gas giant, bold crimson and burnt-orange cloud belts, massive swirling Great Red Oval anticyclone, centered single celestial sphere, isolated on pure deep black space background, 8k resolution, astronomical photography"),
    ("celestial_010", "normal_planet", "mesh_candidate",
     "a crystal silicate planet, iridescent amethyst and quartz mountain spires protruding from dark obsidian plains, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_011", "normal_planet", "mesh_candidate",
     "a dark methane ice dwarf planet, deep navy nitrogen frost plains, fractured blue-gray glacial ridges, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_012", "normal_planet", "mesh_candidate",
     "a carbon exoplanet, pitch-black graphite and soot crust, glistening diamond crystal outcrops catching starlight, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_013", "normal_planet", "mesh_candidate",
     "a bioluminescent jungle planet, glowing neon cyan and violet photosynthetic canopy visible from orbit, misty translucent atmosphere, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_014", "normal_planet", "mesh_candidate",
     "a molten silicate exoplanet, glowing golden-yellow lava seas, smoky basalt calderas, bright volcanic plumes, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_015", "normal_planet", "mesh_candidate",
     "a cold ammonia gas giant, pale cerulean, lavender, and ivory atmospheric jet streams, delicate cirrus ice bands, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_016", "normal_planet", "mesh_candidate",
     "an ancient oxidized terrestrial world, copper-green malachite patina mineral basins, eroded rust plateaus, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_017", "normal_planet", "mesh_candidate",
     "an electric storm gas giant, deep purple and neon cyan swirling storm bands, massive atmospheric lightning networks, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_018", "normal_planet", "mesh_candidate",
     "a vitrified glass planet, iridescent glassy plains formed by ancient meteorite bombardment, shimmering spectral reflections, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_019", "normal_planet", "mesh_candidate",
     "a warm sub-neptune aqua planet, thick translucent aquamarine atmosphere, dense boiling steam cloud decks, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_020", "normal_planet", "mesh_candidate",
     "a volcanic sulphur world, vivid bright yellow, orange, and charcoal sulfur plains, active erupting geysers, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_021", "normal_planet", "mesh_candidate",
     "a frozen nitrogen dwarf planet, pale pink methane frost plains, jagged dark water-ice mountain ridges, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_022", "normal_planet", "mesh_candidate",
     "a chthonian stripped core planet, exposed dense metallic nickel-iron bedrock with iridescent mineral strata, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_023", "normal_planet", "mesh_candidate",
     "a terrestrial planet with scarlet-red alien vegetation covering massive continents, deep sapphire oceans, graceful white cloud swirls, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_024", "normal_planet", "mesh_candidate",
     "a dense shrouded cloud world, completely enveloped in smooth golden-amber atmospheric haze, glowing atmospheric rim, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_025", "normal_planet", "mesh_candidate",
     "a fractured tectonic world, deep glowing orange fault lines tearing through dark charcoal continental crust, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_026", "normal_planet", "mesh_candidate",
     "a calcite marble terrestrial planet, stark pure white mountain ranges, dry turquoise salt sinkholes, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_027", "normal_planet", "mesh_candidate",
     "a hot jupiter gas giant, glowing orange and ruby atmospheric heat bands, dark sodium absorption clouds, intense star illumination, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_028", "normal_planet", "mesh_candidate",
     "a radioactive terrestrial planet, glowing emerald uranium fissures, brilliant green aurorae crowning the polar regions, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_029", "normal_planet", "mesh_candidate",
     "a crystalline quartz world, geometric translucent mineral facets reflecting pinpoint starlight, jagged crystalline plateaus, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_030", "normal_planet", "mesh_candidate",
     "a primordial prebiotic planet, turbulent slate-gray oceans, volcanic island chains, fiery red lightning storm clouds, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_031", "normal_planet", "mesh_candidate",
     "a striped gas giant, elegant alternating navy-blue, mint-green, and bronze cloud bands, delicate atmospheric ripples, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_032", "normal_planet", "mesh_candidate",
     "a salt-flat arid planet, brilliant blinding white sodium crust plains, cracked hexagonal ground patterns, dry rust canyons, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_033", "normal_planet", "mesh_candidate",
     "a tidally locked eyeball planet, central deep sapphire ocean surrounded by perpetual white glacial ice rings and desert margins, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_034", "normal_planet", "mesh_candidate",
     "a super-earth terrestrial world, sprawling turquoise inland seas, ochre savannah plateaus, dense white cloud swirls, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_035", "normal_planet", "mesh_candidate",
     "an obsidian volcanic world, glossy jet-black glassy crust, web-like glowing ruby magma fissures, smoking calderas, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_036", "normal_planet", "mesh_candidate",
     "a pastel gas giant, delicate swirls of soft lilac, mint, and peach ammonia cloud layers, subtle atmospheric depth, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_037", "normal_planet", "mesh_candidate",
     "an iron-oxide terrestrial planet, rich reddish-brown dust storm systems, colossal serpentine canyon chasms, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_038", "normal_planet", "mesh_candidate",
     "a sub-zero ammonia ocean planet, dark teal liquid ammonia oceans, ivory floating ice continents, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_039", "normal_planet", "mesh_candidate",
     "a hydrocarbon swamp planet, shimmering amber liquid methane lakes, dark tarry landmasses, oily iridescent atmospheric sheen, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_040", "normal_planet", "mesh_candidate",
     "a metallic core remnant planet, exposed crystalline iron-nickel lattice structures, polished metallic impact scars, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_041", "normal_planet", "mesh_candidate",
     "an aurora-draped dark gas giant, colossal luminous violet and emerald auroral oval curtains crowning both poles, deep indigo body, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_042", "normal_planet", "mesh_candidate",
     "a columnar basalt rocky world, massive dark geometric hexagonal basalt columns, deep impact craters, sharp shadows, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),

    # --- 15 Ringed Planets (mesh_candidate) ---
    ("celestial_043", "ringed_planet", "mesh_candidate",
     "a golden gas giant with expansive concentric translucent icy rings, delicate ring divisions, sharp planet shadow on rings, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_044", "ringed_planet", "mesh_candidate",
     "a turquoise ice giant with razor-thin bright silver particle rings, smooth cyan atmosphere, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_045", "ringed_planet", "mesh_candidate",
     "a crimson terrestrial world surrounded by a dense rocky asteroid ring system composed of glowing reddish silicate debris, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_046", "ringed_planet", "mesh_candidate",
     "a violet gas giant with iridescent opal-like wide ring system shimmering with prism reflections under starlight, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_047", "ringed_planet", "mesh_candidate",
     "a cobalt ocean planet with a delicate faint icy ring system casting a slender dark shadow across the equator, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_048", "ringed_planet", "mesh_candidate",
     "a dark charcoal volcanic planet encircled by a glowing ring of incandescent fiery volcanic dust and ash, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_049", "ringed_planet", "mesh_candidate",
     "a colossal cream and caramel banded gas giant with sprawling nested ring structures and dark Cassini divisions, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_050", "ringed_planet", "mesh_candidate",
     "an emerald gas world with dual concentric crystalline silicate dust rings, rich green cloud bands, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_051", "ringed_planet", "mesh_candidate",
     "a super-saturn exoplanet with hyper-extended colossal planetary rings spanning millions of kilometers, delicate density waves, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_052", "ringed_planet", "mesh_candidate",
     "a frozen methane world with a dark dusty charcoal ring system tilted at a dramatic 45-degree angle, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_053", "ringed_planet", "mesh_candidate",
     "a gunmetal metallic world with highly reflective iron-dust rings sparkling in the star glare, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_054", "ringed_planet", "mesh_candidate",
     "a pale amber gas giant with intricate braided ring structures carved by gravitational resonances, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_055", "ringed_planet", "mesh_candidate",
     "an obsidian rocky planet surrounded by a razor-sharp shimmering glass shard ring system reflecting starlight, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_056", "ringed_planet", "mesh_candidate",
     "a multi-colored striped gas giant with dual crossing faint crystalline particulate rings, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),
    ("celestial_057", "ringed_planet", "mesh_candidate",
     "a deep sapphire sub-neptune with brilliant white ice particle rings gleaming against deep space, centered celestial sphere with rings, isolated on pure deep black space background, 8k resolution"),

    # --- 8 Black Holes (effect_candidate) ---
    ("celestial_058", "black_hole", "effect_candidate",
     "a supermassive black hole with a blindingly bright incandescent orange-gold relativistic accretion disk, strong gravitational lensing bending the background stars into einstein rings, pitch black event horizon core, centered, isolated in cosmic void, 8k resolution, scientifically accurate general relativity render"),
    ("celestial_059", "black_hole", "effect_candidate",
     "a spinning kerr black hole, asymmetric relativistic doppler beaming with brilliant cyan approaching side, warped photon sphere halo, pitch black central shadow, centered in deep space, 8k resolution"),
    ("celestial_060", "black_hole", "effect_candidate",
     "an intermediate-mass black hole tearing apart interstellar gas, turbulent swirling violet and ultraviolet accretion vortex, intense gravitational distortion, centered in deep black space, 8k resolution"),
    ("celestial_061", "black_hole", "effect_candidate",
     "a stellar-mass black hole with a razor-thin ultra-hot electric blue accretion disk, warped gravitational lensing ring, pitch black event horizon, centered in deep space, 8k resolution"),
    ("celestial_062", "black_hole", "effect_candidate",
     "a luminous quasar black hole with colossal relativistic plasma jets erupting perpendicularly from both poles, blazing white accretion core, centered in deep cosmos, 8k resolution"),
    ("celestial_063", "black_hole", "effect_candidate",
     "an isolated primordial black hole, pure pitch-black spherical void with extreme gravitational microlensing distorting distant stellar fields into concentric rings, centered, 8k resolution"),
    ("celestial_064", "black_hole", "effect_candidate",
     "an active galactic nucleus black hole with a massive ruby-red spiral accretion disk, magnetic plasma flares, intense gravitational warp, centered in deep space, 8k resolution"),
    ("celestial_065", "black_hole", "effect_candidate",
     "a black hole with a swirling golden-yellow gas accretion disk, bright photon ring, severe gravitational space-time curvature, centered in deep black cosmos, 8k resolution"),

    # --- 7 White Holes (effect_candidate) ---
    ("celestial_066", "white_hole", "effect_candidate",
     "a cosmic white hole violently expelling radiant diamond-bright matter and blinding white light into the cosmic void, outward gravitational repulsion waves, centered in deep space, 8k resolution"),
    ("celestial_067", "white_hole", "effect_candidate",
     "a super-energetic white hole with expanding spherical shockwaves of iridescent turquoise and violet photon radiation, brilliant central energy fountain, centered in deep space, 8k resolution"),
    ("celestial_068", "white_hole", "effect_candidate",
     "a temporal white hole core erupting luminous plasma fountains and intense outward gravitational repulsion shockwaves, centered in deep cosmic void, 8k resolution"),
    ("celestial_069", "white_hole", "effect_candidate",
     "a cosmic white hole surrounded by concentric prismatic rings of expelled relativistic energy, golden light flares, glowing matter ejection, centered in deep space, 8k resolution"),
    ("celestial_070", "white_hole", "effect_candidate",
     "a stellar white hole erupting high-velocity stellar matter and brilliant cerulean energy filaments into deep space, radiant glowing core, centered, 8k resolution"),
    ("celestial_071", "white_hole", "effect_candidate",
     "a pulsating white hole emitting rhythmic bursts of blinding pearl-white radiance and relativistic outward matter jets, centered in deep black space, 8k resolution"),
    ("celestial_072", "white_hole", "effect_candidate",
     "a primordial white hole expelling glowing nebula-like gas streams, intense rainbow diffraction spikes, brilliant luminous outward singularity, centered in deep space, 8k resolution"),

    # --- 8 Neutron Stars / Pulsars (mesh_candidate) ---
    ("celestial_073", "neutron_star_pulsar", "mesh_candidate",
     "a millisecond pulsar, ultra-dense glowing cyan sphere, rapid twin conical relativistic radiation beams sweeping through deep space, strong gravitational lensing around the perimeter, centered single celestial object, isolated on pure deep black space background, 8k resolution"),
    ("celestial_074", "neutron_star_pulsar", "mesh_candidate",
     "a magnetar with intense glowing electric-blue magnetic field lines, cracked ultra-dense crust glowing with green x-ray flares, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_075", "neutron_star_pulsar", "mesh_candidate",
     "a classical neutron star, tiny compact sphere glowing blinding white-blue with extreme gravitational lensing curvature halo, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_076", "neutron_star_pulsar", "mesh_candidate",
     "a gamma-ray pulsar with brilliant magenta magnetic polar jets, ultra-dense metallic crust reflecting gamma radiance, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_077", "neutron_star_pulsar", "mesh_candidate",
     "an ultra-dense pulsar sphere glowing deep violet with synchronized pulsing radiation beacons and magnetic arc loops, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_078", "neutron_star_pulsar", "mesh_candidate",
     "a radio pulsar with razor-thin focused golden particle beams shooting from magnetic poles into the cosmos, glowing core, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_079", "neutron_star_pulsar", "mesh_candidate",
     "an accreting neutron star with thermonuclear x-ray burst surface flares glowing radiant orange-white, dense crust, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_080", "neutron_star_pulsar", "mesh_candidate",
     "a glitching pulsar with fractured neutron crust releasing high-energy electromagnetic shockwaves and blue plasma arcs, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),

    # --- 10 Host Stars / Primary Stars (mesh_candidate) ---
    ("celestial_081", "host_star", "mesh_candidate",
     "a yellow G-type main sequence star (Sun-like), bubbling solar granulation cells, dark magnetic sunspots, delicate glowing golden corona and prominences, centered single celestial sphere, isolated on pure deep black space background, 8k resolution, astronomical photography"),
    ("celestial_082", "host_star", "mesh_candidate",
     "a massive Blue Supergiant star, blinding cyan-white incandescent stellar surface, ferocious solar winds, intense ultraviolet radiance, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_083", "host_star", "mesh_candidate",
     "a colossal Red Giant star, pulsating ruby-orange convection cells, billowing gaseous outer envelope, turbulent stellar limb, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_084", "host_star", "mesh_candidate",
     "a Red Dwarf M-type star, deep crimson magnetic active regions, violent stellar flares erupting from the limb, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_085", "host_star", "mesh_candidate",
     "a compact White Dwarf star, ultra-dense blinding diamond-white sphere, extreme surface gravity glow, delicate shimmering corona, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_086", "host_star", "mesh_candidate",
     "a Yellow Supergiant star, complex golden coronal mass ejections, turbulent incandescent plasma granules, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_087", "host_star", "mesh_candidate",
     "an Orange K-type main sequence star, warm amber stellar surface, stable solar atmosphere, graceful coronal loops, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_088", "host_star", "mesh_candidate",
     "a Wolf-Rayet star, violent stellar winds ejecting expanding shells of glowing neon-pink and teal ionized gas around a blazing blue-white core, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_089", "host_star", "mesh_candidate",
     "a Carbon star, deep luminous soot-ruby coloration, dark carbon molecular absorption bands, warm ember-like glow, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),
    ("celestial_090", "host_star", "mesh_candidate",
     "a variable Cepheid star, pulsating golden-white radiant photosphere, dynamic expanding chromosphere, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"),

    # --- 5 Galaxies or Superclusters (background_only) ---
    ("celestial_091", "galaxy_supercluster", "background_only",
     "a grand design spiral galaxy, sweeping cyan starburst arms, bright golden galactic nucleus, intricate dark interstellar dust lanes, deep cosmic space background with distant stars, 8k resolution, Hubble telescope astrophotography"),
    ("celestial_092", "galaxy_supercluster", "background_only",
     "a massive elliptical galaxy, brilliant smooth golden-amber stellar core fading gracefully into a soft halo of billions of stars, deep field astrophotography, 8k resolution"),
    ("celestial_093", "galaxy_supercluster", "background_only",
     "an interacting colliding galaxy pair with long luminous tidal tails, vibrant pink and blue starburst nursery regions, deep cosmic field, 8k resolution"),
    ("celestial_094", "galaxy_supercluster", "background_only",
     "a barred spiral galaxy with a prominent central stellar bar, vivid magenta star-forming nebulae along spiral arms, dark dust filaments, deep space, 8k resolution"),
    ("celestial_095", "galaxy_supercluster", "background_only",
     "a deep field cosmic supercluster with dozens of glowing spiral and elliptical galaxies linked by faint cosmic web filaments across the vast universe, 8k resolution"),

    # --- 5 Asteroid Belts / Cosmic Dust (background_only) ---
    ("celestial_096", "asteroid_belt_dust", "background_only",
     "a dense asteroid belt field with thousands of jagged metallic and rocky planetesimals illuminated by dramatic star illumination, deep cosmic void background, 8k resolution, cinematic space photography"),
    ("celestial_097", "asteroid_belt_dust", "background_only",
     "an interstellar molecular dust cloud with rich amber, indigo, and violet nebular dust filaments backlit by embedded proto-stars, deep space astrophotography, 8k resolution"),
    ("celestial_098", "asteroid_belt_dust", "background_only",
     "a primordial protoplanetary debris disk composed of churning silica dust, icy gravel rings, and micro-meteorite swarms around a stellar plane, deep space, 8k resolution"),
    ("celestial_099", "asteroid_belt_dust", "background_only",
     "a cometary debris swarm with thousands of icy asteroid fragments trailing delicate glowing cyan vapor tails through the cosmic void, 8k resolution"),
    ("celestial_100", "asteroid_belt_dust", "background_only",
     "a supernova remnant dust veil with intricate gossamer filaments of glowing ionized iron, sulfur, and hydrogen gas expanding into deep space, 8k resolution")
]

def init_manifest():
    if os.path.exists(MANIFEST_PATH):
        print("[Manifest] Loading existing manifest from " + MANIFEST_PATH)
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        if len(manifest) == len(PROMPTS_DATA):
            return manifest

    print("[Manifest] Initializing new manifest with " + str(len(PROMPTS_DATA)) + " items...")
    manifest = []
    base_seed = 420001
    for i, (cid, cat, role, prompt) in enumerate(PROMPTS_DATA):
        seed = base_seed + i * 7919
        item = {
            "id": cid,
            "category": cat,
            "asset_role": role,
            "prompt": prompt,
            "negative_prompt": COMMON_NEGATIVE,
            "seed": seed,
            "output_file": cid + "_00001_.png",
            "status": "pending",
            "error": ""
        }
        manifest.append(item)

    save_manifest(manifest)
    return manifest

def save_manifest(manifest):
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    temp_path = MANIFEST_PATH + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
    os.replace(temp_path, MANIFEST_PATH)

def build_workflow(item):
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
                "steps": 30
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
                "filename_prefix": OUTPUT_SUBDIR + "/" + item["id"],
                "images": ["8", 0]
            }
        }
    }

def queue_prompt(prompt_workflow):
    payload = {"prompt": prompt_workflow, "client_id": CLIENT_ID}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request("http://" + SERVER_ADDRESS + "/prompt", data=data, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def get_history(prompt_id):
    req = urllib.request.Request("http://" + SERVER_ADDRESS + "/history/" + prompt_id, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def generate_item(item, max_wait_sec=180):
    item_id = item["id"]
    expected_output_path = os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR, item["output_file"])
    
    # Check if already completed and file exists
    if item["status"] == "completed" and os.path.exists(expected_output_path) and os.path.getsize(expected_output_path) > 1024:
        print("[" + item_id + "] Already completed (" + expected_output_path + "). Skipping.")
        return True

    print("[" + item_id + "] [" + item["category"] + "] (" + item["asset_role"] + ") Queuing prompt (Seed: " + str(item["seed"]) + ")...")
    wf = build_workflow(item)
    try:
        res = queue_prompt(wf)
        prompt_id = res.get("prompt_id")
        if not prompt_id:
            err = "No prompt_id returned in API response: " + str(res)
            item["status"] = "failed"
            item["error"] = err
            return False
    except Exception as e:
        err = "Failed to queue prompt via API: " + str(e)
        item["status"] = "failed"
        item["error"] = err
        return False

    # Poll history until finished
    start_time = time.time()
    while time.time() - start_time < max_wait_sec:
        time.sleep(1.5)
        try:
            hist = get_history(prompt_id)
            if prompt_id in hist:
                outputs = hist[prompt_id].get("outputs", {})
                status_info = hist[prompt_id].get("status", {})
                if status_info.get("status_str") == "error":
                    err = "ComfyUI execution error: " + str(status_info.get("messages"))
                    item["status"] = "failed"
                    item["error"] = err
                    return False
                
                # Check output file on disk
                if os.path.exists(expected_output_path) and os.path.getsize(expected_output_path) > 1024:
                    item["status"] = "completed"
                    item["error"] = ""
                    duration = time.time() - start_time
                    size_mb = os.path.getsize(expected_output_path) / (1024 * 1024)
                    print("[" + item_id + "] Completed in " + str(round(duration, 1)) + "s | Size: " + str(round(size_mb, 2)) + " MB")
                    return True
                else:
                    # Look for actual generated filename in output dir
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
                            print("[" + item_id + "] Completed in " + str(round(duration, 1)) + "s | File: " + actual_fn + " (" + str(round(size_mb, 2)) + " MB)")
                            return True
                    
                    time.sleep(1.0)
                    if os.path.exists(expected_output_path):
                        item["status"] = "completed"
                        item["error"] = ""
                        return True
        except Exception:
            pass

    item["status"] = "failed"
    item["error"] = "Timeout waiting for prompt " + prompt_id + " after " + str(max_wait_sec) + "s"
    print("[" + item_id + "] Failed: " + item["error"])
    return False

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "full"
    manifest = init_manifest()
    
    if mode == "test":
        print("\n=== RUNNING 1 SINGLE TEST IMAGE (celestial_001) ===")
        test_item = manifest[0]
        test_success = generate_item(test_item, max_wait_sec=120)
        save_manifest(manifest)
        if test_success:
            print("=== TEST IMAGE PASSED ===")
            sys.exit(0)
        else:
            print("=== TEST IMAGE FAILED: " + test_item["error"] + " ===")
            sys.exit(1)

    elif mode == "full":
        print("\n=== STARTING SEQUENTIAL BATCH GENERATION (100 items) ===")
        total = len(manifest)
        completed_count = sum(1 for x in manifest if x["status"] == "completed")
        failed_count = sum(1 for x in manifest if x["status"] == "failed")
        
        print("Initial State: " + str(completed_count) + " completed, " + str(failed_count) + " failed, " + str(total - completed_count) + " pending.\n")
        
        for idx, item in enumerate(manifest):
            if item["status"] == "completed":
                continue
            
            print("--- Processing [" + str(idx+1) + "/" + str(total) + "] (" + item["id"] + ") ---")
            success = generate_item(item)
            save_manifest(manifest)
            
            if not success:
                print("Warning: Item " + item["id"] + " failed. Error: " + item["error"])
            
            sys.stdout.flush()
        
        final_completed = sum(1 for x in manifest if x["status"] == "completed")
        final_failed = sum(1 for x in manifest if x["status"] == "failed")
        final_pending = sum(1 for x in manifest if x["status"] == "pending")
        
        print("\n=== BATCH SUMMARY ===")
        print("Total: " + str(total))
        print("Completed: " + str(final_completed))
        print("Failed: " + str(final_failed))
        print("Pending: " + str(final_pending))
        print("Manifest: " + MANIFEST_PATH)
        print("Output Directory: " + os.path.join(COMFY_OUTPUT_ROOT, OUTPUT_SUBDIR))
        
        if final_completed == total:
            print("ALL 100 CELESTIAL IMAGES COMPLETED PERFECTLY!")
            sys.exit(0)
        else:
            print("Batch finished with " + str(final_failed) + " failures.")
            sys.exit(1)
