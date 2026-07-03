# Eclipse - A Bliss Edit

Bliss is already one of the best and most feature rich shaders out there, yet I still wanted more...  
It started out with smaller features, but then the additions just kept piling up.

Notable changes/additions compared to Bliss unstable:
 + Custom moon orbit with possible eclipses
 + Water wave simulation for the player
 + Shader Grass
 + Aurora & Rainbow
 + Additional cirrus & cumulonimbus cloud layers (WIP)
 + Distant Horizons chunk fading
 + Moon Texture with phases
 + Snow Overlay and Rain Ripples
 + Better shader-side (hardcoded) emissives
 + Lightsource with shadows on the main end island
 + Better lightning strikes with clouds lighting up and shadows
 + Photonics, Caelum (Arda Craft) support
 + 1.21.11 Chunk Fade In support
 + Emissive Ores and Trims

Note: With default settings there is at least one guaranteed eclipse per ingame year.

## Eclipses <sub>(why else would I call the shader Eclipse??)</sub>

<img width="2560" height="1440" alt="2025-08-12_02 16 11" src="https://github.com/user-attachments/assets/8b2a1161-8bb5-4003-b04c-16a9c6f01494" />

## Overhauled end lighting for the main island

<img width="2560" height="1440" alt="2025-08-12_01 31 12" src="https://github.com/user-attachments/assets/a1a408cc-ed2a-46a3-a465-4b09d0d00660" />

## Water wave simulation

<img width="1920" height="1080" alt="2025-09-02_00 29 28" src="https://github.com/user-attachments/assets/87cbd02c-1149-4764-9ff0-7da521b0273a" />

## Shader Snow

<img width="1920" height="1080" alt="2025-08-13_13 38 18" src="https://github.com/user-attachments/assets/31e5102e-d872-4aec-a606-39ae88385d45" />

## Shader Grass

<img width="1920" height="1080" alt="2025-10-06_01 34 47" src="https://github.com/user-attachments/assets/47dfabab-51cf-4490-9247-35f7879a3690" />

## Lightning Shadows

<img width="2560" height="1440" alt="2025-08-12_02 52 02" src="https://github.com/user-attachments/assets/5f8c484f-2574-4a07-857b-9347c4b459c2" />

## Moon Texture with physically correct lighting

<img width="1920" height="1080" alt="2025-08-16_23 14 00" src="https://github.com/user-attachments/assets/1e92cf5f-9a28-47a0-8737-36853034ff68" />

## Rainbows

<img width="1920" height="1080" alt="2025-08-16_21 34 11" src="https://github.com/user-attachments/assets/618bf00e-d4f6-4336-87d9-79fb65e18775" />


### SPECIAL THANKS:
+ Chocapic13, for the base shader
+ Xonk, for developing the great Bliss shader
+ WoMspace, for spending alot of time creating a DOF overhaul
+ Null, for doing a huge amount of work creating the voxel floodfill colored lighting
+ Emin, and Gri573, for teaching me how to stop alot of light leaking
+ RRe36 and Sixthsurge, for the great ideas to steal
### [Want to support Xonk? Consider donating](https://ko-fi.com/xonkdev)

### [You can contact me by joining Xonk's discord server and using the Eclipse channel!](https://discord.gg/8nVt56H9zH)


# How to download the latest version:
 - locate the `green "code" button` on this page. this button is NOT in the `releases` page.
 - click the `green "code" button` and select `"download zip"`.
 - once the zip file finishes downloading, install it like a normal shader. you do NOT need to unzip/extract/decompress.

# Incompatible Mods / Mods with issues
- Iris (on MC 26.2)
- Chunks Fade In mod
- Puddles and Floods
- Create Aeronautics
- BBS (disable shader curves setting in BBS settings)
- Iris Uniforms
- Epic Fight Mod (disable the compute shader setting in the Epic Fight Mod settings)
- Particle Rain
- Physics Mod (Smoke, Fluid Sim and Weather)

# You want MOAR performance?
> [!NOTE]  
> My "[Iris Extension](https://modrinth.com/mod/iris-extension)" mod automatically does this when shader grass is disabled, there is no need to manually delete the files if you are using my mod!

 Delete the "gbuffers_terrain.gsh", "gbuffers_terrain.tcs" and "gbuffers_terrain.tes" files for all world folders in the shader.
 This will make the shader grass setting non functional BUT will increase performance, especially with high vanilla render distances!
 (If you're wondering why, Iris does NOT allow me to disable these files once they're there. So even when Shader Grass is disabled these execute and harm performance!)
