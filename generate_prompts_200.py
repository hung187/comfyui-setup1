import sys
import os
import json

# Define the 200 prompts programmatically with high descriptive quality and diversity

def generate_prompts_200():
    prompts = []
    
    # 1. Normal Planets: 110 items (celestial_200_001 to celestial_200_110)
    normal_planet_templates = [
        # Terrestrial / Ocean / Biome planets (30)
        "a photorealistic super-earth terrestrial planet with vibrant azure oceans, emerald green lush continents, swirling white atmospheric storm systems, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, subtle blue atmospheric limb glow, 8k resolution, cinematic space photography",
        "a deep sapphire water world completely covered by a global ocean, dynamic white cyclonic typhoon vortices, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, crisp specular starlight glint, 8k resolution",
        "a terrestrial exoplanet with scarlet-red alien vegetation covering sprawling landmasses, deep turquoise inland seas, elegant white cloud patterns, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a tropical archipelago world with thousands of turquoise coral atolls and island chains scattered across a brilliant cerulean ocean, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a primeval Pangaea terrestrial planet with a single massive supercontinent surrounded by a vast cobalt ocean, mountain ranges, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a bioluminescent jungle planet, glowing neon-cyan and electric-magenta photosynthetic canopy visible from orbit in the twilight hemisphere, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "an ancient oxidized terrestrial planet with copper-green malachite patina mineral basins, eroded rust-orange plateaus, shallow teal lakes, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a tidally locked eyeball planet, central deep sapphire ocean surrounded by concentric rings of white glacial ice and arid terracotta desert margins, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a super-habitable planet with expansive shallow jade-green seas, rolling golden-amber savannas, crisp white atmospheric cloud bands, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a misty swamp planet enveloped in translucent pale-emerald atmospheric haze, intricate winding waterways, dark olive marshlands, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        
        # Volcanic / Magma / Molten planets (20)
        "a glowing volcanic planet with incandescent molten lava rivers spiderwebbing across fractured dark basalt tectonic plates, active glowing calderas, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "an obsidian molten world with glossy jet-black glassy crust, web-like glowing ruby magma fissures, smoking volcanic hotspots, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a sulfur volcanic planet covered in vivid canary-yellow, ochre, and charcoal sulfur plains, active erupting magma geysers, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a hyper-thermal magma exoplanet with boiling golden-yellow lava seas, incandescent smoky basalt islands, intense thermal glow, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a fractured magma world with deep radiant violet-red lava trenches tearing through dark titanium crust, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        
        # Ice / Cryo / Frozen worlds (20)
        "a frozen ice giant cryo-world, translucent turquoise glacial ice sheets, deep cobalt nitrogen frost chasms, delicate pale cyan vapor haze, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a frozen nitrogen dwarf planet with pale pink methane frost plains, jagged dark water-ice mountain ridges, crisp polar caps, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a snowball terrestrial planet completely encased in cracked brilliant white and cerulean sea-ice plates, deep glacial rift valleys, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a dark methane ice planet with deep navy nitrogen frost plains, fractured blue-gray glacial ridges, sharp crystalline highlights, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a cryovolcanic planet with frozen ammonia plains, active brilliant cyan cryogenic geysers spraying vapor into space, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        
        # Desert / Arid / Mineral / Barren worlds (20)
        "an arid desert rocky planet, vast terracotta canyons, golden sand dune oceans, dusty ochre atmospheric limb, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a stark cratered barren planet, slate-gray lunar regolith surface, deep ancient impact basins, bright crater ray systems, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a metallic iron-rich terrestrial world, reflective gunmetal gray mineral crust, polished impact scars, sharp specular highlights, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a salt-flat arid planet, brilliant blinding white sodium crust plains, cracked hexagonal ground patterns, dry rust canyons, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a crystal silicate planet, iridescent amethyst and quartz mountain spires protruding from dark obsidian plains, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        
        # Gas Giants / Atmospheric worlds (20)
        "a turbulent gas giant, bold crimson and burnt-orange cloud belts, massive swirling Great Red Oval anticyclone storm, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a cold ammonia gas giant, pale cerulean, lavender, and ivory atmospheric jet streams, delicate cirrus ice cloud bands, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "an electric storm gas giant, deep purple and neon-cyan swirling storm bands, massive atmospheric lightning networks visible across the cloud tops, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a pastel gas giant, delicate swirls of soft lilac, mint-green, and peach ammonia cloud layers, subtle atmospheric depth, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a hot jupiter gas giant, glowing orange and ruby atmospheric heat bands, dark sodium absorption clouds, intense star illumination, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution"
    ]
    
    # Generate 110 unique normal planet prompts by extending with distinct adjectives and geological/atmospheric features
    subtypes = [
        ("super-earth with archipelagos", "lush turquoise island chains and deep ultramarine ocean basins"),
        ("glacial tundra world", "cracked pale blue permafrost plains and dark granite mountain chains"),
        ("golden sand desert world", "massive rippling dune seas and dramatic red sandstone plateaus"),
        ("toxic venutian world", "dense golden-sulfur cloud swirls and veiled acidic atmosphere"),
        ("chlorophyll rich world", "vibrant teal photosynthetic continents and clear cyan seas"),
        ("ferrous red planet", "deep scarlet rust canyons and white dry-ice polar ice sheets"),
        ("prismatic crystal world", "glistening quartz crystal formations reflecting specular starlight across dark basalt plains"),
        ("stormy gas giant", "alternating indigo, emerald, and cream atmospheric jet streams with colossal cyclone vortices"),
        ("radioactive mineral world", "glowing emerald uranium mineral veins and luminous green aurora curtains"),
        ("chthonian stripped core planet", "exposed nickel-iron metallic strata and iridescent polished mineral craters"),
        ("steamy sub-neptune", "dense aquamarine vapor envelope and deep churning liquid water mantle")
    ]
    
    idx = 1
    for template in normal_planet_templates:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "normal_planet", "mesh_candidate", template))
        idx += 1
        if idx > 110:
            break
            
    while idx <= 110:
        sub_name, sub_desc = subtypes[(idx - 1) % len(subtypes)]
        color_variants = ["azure and emerald", "ruby and obsidian", "amethyst and silver", "topaz and terracotta", "sapphire and pearl", "jade and bronze", "cobalt and gold", "charcoal and copper"]
        col = color_variants[(idx * 3) % len(color_variants)]
        p = f"a photorealistic {sub_name} exoplanet with {sub_desc}, rich {col} color palette, centered single celestial sphere occupying 70% of the frame, orthographic asset view, isolated on pure deep black space background, subtle atmospheric rim glow, 8k resolution, cinematic space photography"
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "normal_planet", "mesh_candidate", p))
        idx += 1

    # 2. Ringed Planets: 35 items (celestial_200_111 to celestial_200_145)
    ringed_planet_templates = [
        "a majestic golden gas giant with expansive concentric translucent icy rings, delicate ring divisions, sharp planet shadow cast onto rings, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a turquoise ice giant with razor-thin bright silver particulate rings, smooth cyan atmosphere, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a crimson terrestrial world encircled by a dense rocky asteroid ring system composed of glowing reddish silicate debris, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a violet gas giant with iridescent opal-like wide ring system shimmering with prism reflections under starlight, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a cobalt ocean planet with a delicate faint icy ring system casting a slender dark shadow across the equator, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a dark charcoal volcanic planet encircled by a glowing ring of incandescent fiery volcanic dust and ash, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a colossal cream and caramel banded gas giant with sprawling nested ring structures and dark Cassini divisions, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "an emerald gas world with dual concentric crystalline silicate dust rings, rich green cloud bands, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a super-saturn exoplanet with hyper-extended colossal planetary rings spanning millions of kilometers, delicate density waves, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a frozen methane world with a dark dusty charcoal ring system tilted at a dramatic 45-degree angle, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a gunmetal metallic world with highly reflective iron-dust rings sparkling in the star glare, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a pale amber gas giant with intricate braided ring structures carved by gravitational resonances, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "an obsidian rocky planet surrounded by a razor-sharp shimmering glass shard ring system reflecting starlight, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a multi-colored striped gas giant with dual crossing faint crystalline particulate rings, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution",
        "a deep sapphire sub-neptune with brilliant white ice particle rings gleaming against deep space, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution"
    ]
    
    for template in ringed_planet_templates:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "ringed_planet", "mesh_candidate", template))
        idx += 1
        
    while idx <= 145:
        r_var = [
            ("pearl-white gas planet", "sprawling concentric ice crystal rings", "soft lavender atmospheric bands"),
            ("copper terrestrial planet", "dense bronze mineral debris rings", "canyons and shallow rust lakes"),
            ("aquamarine ice giant", "delicate multi-tiered silver rings", "smooth cyan cloud deck"),
            ("obsidian crystal planet", "shimmering diamond-shard dust rings", "black basalt crust with glowing veins"),
            ("golden-yellow gas giant", "ultra-wide nested rings with dark divisions", "swirling amber cyclone belts")
        ]
        p_name, r_desc, a_desc, = r_var[(idx - 1) % len(r_var)]
        p = f"a photorealistic {p_name} with {a_desc}, encircled by {r_desc} casting a distinct planet shadow, centered single celestial sphere with rings occupying 75% of the frame, orthographic asset view, isolated on pure deep black space background, 8k resolution, cinematic space photography"
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "ringed_planet", "mesh_candidate", p))
        idx += 1

    # 3. Host Stars: 10 items (celestial_200_146 to celestial_200_155)
    host_star_prompts = [
        "a yellow G-type main sequence star (Sun-like), bubbling solar granulation cells, dark magnetic sunspots, delicate glowing golden corona and prominences, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution, astronomical photography",
        "a massive Blue Supergiant star, blinding cyan-white incandescent stellar surface, ferocious solar winds, intense ultraviolet radiance, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a colossal Red Giant star, pulsating ruby-orange convection cells, billowing gaseous outer envelope, turbulent stellar limb, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a Red Dwarf M-type star, deep crimson magnetic active regions, violent stellar flares erupting from the limb, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a compact White Dwarf star, ultra-dense blinding diamond-white sphere, extreme surface gravity glow, delicate shimmering corona, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a Yellow Supergiant star, complex golden coronal mass ejections, turbulent incandescent plasma granules, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "an Orange K-type main sequence star, warm amber stellar surface, stable solar atmosphere, graceful coronal loops, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a Wolf-Rayet star, violent stellar winds ejecting expanding shells of glowing neon-pink and teal ionized gas around a blazing blue-white core, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a Carbon star, deep luminous soot-ruby coloration, dark carbon molecular absorption bands, warm ember-like glow, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution",
        "a variable Cepheid star, pulsating golden-white radiant photosphere, dynamic expanding chromosphere, centered single celestial sphere occupying 70% of the frame, isolated on pure deep black space background, 8k resolution"
    ]
    for p in host_star_prompts:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "host_star", "mesh_candidate", p))
        idx += 1

    # 4. Neutron Stars / Pulsars: 10 items (celestial_200_156 to celestial_200_165)
    pulsar_prompts = [
        "a millisecond pulsar, ultra-dense glowing cyan sphere, rapid twin conical relativistic radiation beams sweeping through deep space, strong gravitational lensing around the perimeter, centered single celestial object, isolated on pure deep black space background, 8k resolution",
        "a magnetar with intense glowing electric-blue magnetic field lines, cracked ultra-dense crust glowing with green x-ray flares, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "a classical neutron star, tiny compact sphere glowing blinding white-blue with extreme gravitational lensing curvature halo, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "a gamma-ray pulsar with brilliant magenta magnetic polar jets, ultra-dense metallic crust reflecting gamma radiance, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "an ultra-dense pulsar sphere glowing deep violet with synchronized pulsing radiation beacons and magnetic arc loops, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "a radio pulsar with razor-thin focused golden particle beams shooting from magnetic poles into the cosmos, glowing core, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "an accreting neutron star with thermonuclear x-ray burst surface flares glowing radiant orange-white, dense crust, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "a glitching pulsar with fractured neutron crust releasing high-energy electromagnetic shockwaves and blue plasma arcs, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "a binary-companion pulsar drawing a slender glowing filament of hot helium plasma from an unseen neighbor, intense blue magnetic poles, centered single celestial sphere, isolated on pure deep black space background, 8k resolution",
        "a hyper-magnetic neutron star crowned with emerald auroral synchrotron radiation arcs and blinding polar beacons, centered single celestial sphere, isolated on pure deep black space background, 8k resolution"
    ]
    for p in pulsar_prompts:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "neutron_star_pulsar", "mesh_candidate", p))
        idx += 1

    # 5. Black Holes: 10 items (celestial_200_166 to celestial_200_175)
    black_hole_prompts = [
        "a supermassive black hole with a blindingly bright incandescent orange-gold relativistic accretion disk, strong gravitational lensing bending the background stars into einstein rings, pitch black event horizon core, centered, isolated in cosmic void, 8k resolution, scientifically accurate general relativity render",
        "a spinning kerr black hole, asymmetric relativistic doppler beaming with brilliant cyan approaching side, warped photon sphere halo, pitch black central shadow, centered in deep space, 8k resolution",
        "an intermediate-mass black hole tearing apart interstellar gas, turbulent swirling violet and ultraviolet accretion vortex, intense gravitational distortion, centered in deep black space, 8k resolution",
        "a stellar-mass black hole with a razor-thin ultra-hot electric blue accretion disk, warped gravitational lensing ring, pitch black event horizon, centered in deep space, 8k resolution",
        "a luminous quasar black hole with colossal relativistic plasma jets erupting perpendicularly from both poles, blazing white accretion core, centered in deep cosmos, 8k resolution",
        "an isolated primordial black hole, pure pitch-black spherical void with extreme gravitational microlensing distorting distant stellar fields into concentric rings, centered, 8k resolution",
        "an active galactic nucleus black hole with a massive ruby-red spiral accretion disk, magnetic plasma flares, intense gravitational warp, centered in deep space, 8k resolution",
        "a black hole with a swirling golden-yellow gas accretion disk, bright photon ring, severe gravitational space-time curvature, centered in deep black cosmos, 8k resolution",
        "a micro black hole surrounded by a hyper-dense glowing magenta Hawking radiation halo and warped photon ring, centered in deep space, 8k resolution",
        "a dormant black hole silhouetted against a distant cosmic star field, pure circular shadow with delicate dual Einstein lensing rings, centered in deep black cosmos, 8k resolution"
    ]
    for p in black_hole_prompts:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "black_hole", "effect_candidate", p))
        idx += 1

    # 6. White Holes: 10 items (celestial_200_176 to celestial_200_185)
    white_hole_prompts = [
        "a cosmic white hole violently expelling radiant diamond-bright matter and blinding white light into the cosmic void, outward gravitational repulsion waves, centered in deep space, 8k resolution",
        "a super-energetic white hole with expanding spherical shockwaves of iridescent turquoise and violet photon radiation, brilliant central energy fountain, centered in deep space, 8k resolution",
        "a temporal white hole core erupting luminous plasma fountains and intense outward gravitational repulsion shockwaves, centered in deep cosmic void, 8k resolution",
        "a cosmic white hole surrounded by concentric prismatic rings of expelled relativistic energy, golden light flares, glowing matter ejection, centered in deep space, 8k resolution",
        "a stellar white hole erupting high-velocity stellar matter and brilliant cerulean energy filaments into deep space, radiant glowing core, centered, 8k resolution",
        "a pulsating white hole emitting rhythmic bursts of blinding pearl-white radiance and relativistic outward matter jets, centered in deep black space, 8k resolution",
        "a primordial white hole expelling glowing nebula-like gas streams, intense rainbow diffraction spikes, brilliant luminous outward singularity, centered in deep space, 8k resolution",
        "an exotic white hole releasing cascades of antimatter annihilation flashes and emerald outward light shells into deep space, centered, 8k resolution",
        "a white hole event horizon singularity blazing with infinite outward luminance and curved space-time expulsion rings, centered in deep cosmic void, 8k resolution",
        "a newborn white hole bursting forth with radiant golden-yellow plasma shocks and crystalline photon ripples expanding into deep space, centered, 8k resolution"
    ]
    for p in white_hole_prompts:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "white_hole", "effect_candidate", p))
        idx += 1

    # 7. Galaxies or Superclusters: 10 items (celestial_200_186 to celestial_200_195)
    galaxy_prompts = [
        "a grand design spiral galaxy, sweeping cyan starburst arms, bright golden galactic nucleus, intricate dark interstellar dust lanes, deep cosmic space background with distant stars, 8k resolution, Hubble telescope astrophotography",
        "a massive elliptical galaxy, brilliant smooth golden-amber stellar core fading gracefully into a soft halo of billions of stars, deep field astrophotography, 8k resolution",
        "an interacting colliding galaxy pair with long luminous tidal tails, vibrant pink and blue starburst nursery regions, deep cosmic field, 8k resolution",
        "a barred spiral galaxy with a prominent central stellar bar, vivid magenta star-forming nebulae along spiral arms, dark dust filaments, deep space, 8k resolution",
        "a deep field cosmic supercluster with dozens of glowing spiral and elliptical galaxies linked by faint cosmic web filaments across the vast universe, 8k resolution",
        "a ring galaxy with a bright blue ring of young massive stars encircling a golden central core after a direct cosmic collision, 8k resolution",
        "a lenticular galaxy with a bright disk of old stars and a prominent central bulge, delicate dust ring, deep space astrophotography, 8k resolution",
        "a dwarf irregular galaxy sparkling with thousands of brilliant blue starburst clusters and diffuse magenta ionized hydrogen nebulae, 8k resolution",
        "a pinwheel spiral galaxy viewed face-on, displaying luminous azure spiral arms and hundreds of ruby H II star-forming regions, 8k resolution",
        "a giant starburst galaxy expelling colossal superwinds of hot ionized red gas perpendicular to the galactic disk, deep space, 8k resolution"
    ]
    for p in galaxy_prompts:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "galaxy_supercluster", "background_only", p))
        idx += 1

    # 8. Asteroid Belts / Cosmic Dust: 5 items (celestial_200_196 to celestial_200_200)
    belt_prompts = [
        "a dense asteroid belt field with thousands of jagged metallic and rocky planetesimals illuminated by dramatic star illumination, deep cosmic void background, 8k resolution, cinematic space photography",
        "an interstellar molecular dust cloud with rich amber, indigo, and violet nebular dust filaments backlit by embedded proto-stars, deep space astrophotography, 8k resolution",
        "a primordial protoplanetary debris disk composed of churning silica dust, icy gravel rings, and micro-meteorite swarms around a stellar plane, deep space, 8k resolution",
        "a cometary debris swarm with thousands of icy asteroid fragments trailing delicate glowing cyan vapor tails through the cosmic void, 8k resolution",
        "a supernova remnant dust veil with intricate gossamer filaments of glowing ionized iron, sulfur, and hydrogen gas expanding into deep space, 8k resolution"
    ]
    for p in belt_prompts:
        cid = f"celestial_200_{idx:03d}"
        prompts.append((cid, "asteroid_belt_dust", "background_only", p))
        idx += 1

    return prompts

if __name__ == "__main__":
    p_list = generate_prompts_200()
    print(f"Generated {len(p_list)} prompts successfully.")
    cats = {}
    for item in p_list:
        cats[item[1]] = cats.get(item[1], 0) + 1
    for k, v in cats.items():
        print(f"  {k}: {v}")
