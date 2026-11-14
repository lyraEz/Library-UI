# Lyra Shaders

Client-side shaders for any Roblox game, with a Lyra UI panel: colour grading, LUTs, ambient occlusion, real-time reflections, global illumination, depth of field, eye adaptation, lens flares and more. Everything runs on your device only. Other players never see it, and turning it off puts the game's own look back.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/lyraEz/Library-UI/main/shaders/LyraShaders.lua"))()
```

Running it again replaces the running copy. RightControl or `/shaders` in chat shows and hides the window; the **Shaders: On** button on the side of the screen switches the whole engine; `/fx on`, `/fx off` and `/fx <look>` work from chat.

## The window

- **Home**: the engine switch, a live summary, one-tap looks (Natural, Cinematic, Vivid, Noir, Dreamy, Golden hour), the quality level and favourite effects.
- **Effects**: every effect in a list. On / Off switches it in place; the arrow opens its page with all of its settings, a live status line, Reset and a short "How it works".
- **Settings**: the window's own settings, then auto quality, the target frame rate, a key to switch the engine, the Shaders button, copy / import of all settings, restore defaults and unload.
- **Statistics**: frame-rate graph, frame and engine time, rays per second, reflections, shading cards, lights, memory and the cost of each effect.
- **About**: how each effect is made.

Changes save by themselves to `workspace/LyraShaders/settings.json` (executors with `writefile`).

## Effects

| Effect | What it does | How it is built |
|---|---|---|
| Colour | Brightness, contrast, saturation, white balance (temperature and tint) and ten tones | A colour correction layer; Retro and Filmic also use Roblox's tonemapper where available |
| LUT | Ten built-in looks, `.cube` files (1D and 3D) and ReShade PNG strips | The table is decoded (PNG included), measured and fitted to a colour correction layer |
| MXAO | Soft shading where objects meet floors and ceilings, contact shadows, bounce light | Shading cards laid along each crease near you; round contact shadows under characters |
| SSR | Real-time reflections of players, you and the world on floors, walls, ceilings and water | Mirrored copies under a locally see-through floor; mirrors on walls; see below |
| Global Illumination | Light bouncing off sunlit surfaces onto their neighbours, colour bleeding | A light probe finds the brightest sunlit surfaces and places soft lights of their colour |
| Ambient light | Lifts shadows with the colour of the light around you | The probe's average colour added to the ambient light |
| Depth of field | Focus and blur with a thin-lens model (focal length, f-stop, focus distance) | Depth-of-field layer driven by the lens maths; auto, character or manual focus |
| Exposure | Eye adaptation: opens up indoors, closes down toward the sky | Rays across the screen meter the scene; exposure drifts toward a balanced level |
| Lens flare | Ghosts, halo, anamorphic streaks, lens dirt, flares from lamps | Screen overlay; rays toward the sun fade it behind trees and walls |
| Sharpness | Clarity and local contrast; can remove the game's blur | A contrast layer; the game's blur layers are switched off while it is on |
| Deband | Breaks up banding in skies and fog | A fine moving dither generated on the device |
| Zeal Rim Light | A bright edge that lifts characters off the background | Outlines plus a small light behind each character |
| Bloom, Sun rays | Glow and light shafts | Roblox's own layers on top of the game's |
| Atmosphere | Fog density, horizon, haze, glare, colour | Tunes the game's Atmosphere or adds one |
| Vignette, Film grain, Motion blur | The usual camera effects | Overlays and a blur that follows the camera's turn speed |
| Lighting & shadows | Lock the time of day, sun strength, shadow softness, lighting technology | Lighting properties; the technology needs `sethiddenproperty` |

## How the reflections work

**Floors** reflect like a wet or polished floor, all the way to the horizon. A ray down from your character finds the floor height. Everything near you that stands above it (players, you, NPCs and the map) is copied and mirrored under the floor, and the floor parts around you turn partly see-through on your screen only (`LocalTransparencyModifier`, which other players never see). Parts right under a reflective floor are hidden while it reflects, and parts sunk into the floor are trimmed so their copies never poke through. Because the reflection is real geometry, the game's renderer handles depth, lighting and distance: anything in front of the floor hides its reflection, and neon parts and lamps glow in it.

How much a floor part shows the reflection depends on Strength, the angle you see it at (Fresnel), its distance (Distance fade) and, with Follow materials on, its material: marble, glass, metal, ceramic and polished plastic reflect most; grass, fabric and brick least.

**Walls** (and terrain ground, and floors that sit on terrain) get mirrors: a thin invisible part on the surface carrying a SurfaceGui and a ViewportFrame with mirrored copies of the scene, seen from your camera through an off-axis projection so it lines up from any angle.

**Water** uses Roblox's own water reflections, turned up with Strength.

## Limits

Roblox gives scripts no pixel shaders, so these are the honest trade-offs:

- Floor reflections need the floor to be parts (blocks, meshes or unions). Terrain cannot be made see-through, so terrain ground and floors lying on terrain get a mirror instead, which reaches less far at very low angles (Roblox cameras stop at 120° of view).
- While a floor reflects, it is partly see-through on your screen, so its own shadows look lighter, and what is right under it is hidden.
- Copies keep their own handedness, so text and asymmetric meshes are not flipped. Wall mirrors use simple lighting (no shadows or point lights).
- MXAO, Global Illumination and Exposure are built in the world from raycasts, not from the depth buffer. They are approximations of the shader effects with the same names.
- Sharpness raises local contrast; Roblox has no sharpening filter.
- Deband uses an EditableImage when the game allows it, and a light glyph pattern when it does not.
- The lighting technology can only change on executors with `sethiddenproperty`.

## Phones

The engine starts on the Low quality level on phones and tablets, and auto quality (Settings) does less work whenever the frame rate drops below the target. Reflections and MXAO are the heaviest effects; lower Reflected objects on the SSR page if the frame rate drops. Statistics shows what each effect costs.

## LUT files

Put `.cube` files or ReShade strips (`N²` × `N` PNG, for example 1024 × 32) in `workspace/LyraShaders/luts`, then tap **Reload** on the LUT page. A link to a file (`https://…`) also works.

## Script API

```lua
local Shaders = getgenv().LyraShaders
Shaders.SetEnabled("ssr", true)          -- effect ids: colour, lut, mxao, ssr, gi, ambient, dof, exposure, flare, sharpness, ...
Shaders.Set("ssr", "Strength", 80)       -- any parameter shown on an effect's page
Shaders.ApplyLook("Cinematic")
local text = Shaders.Export()            -- every setting as JSON (also copied to the clipboard)
Shaders.Import(text)
Shaders.Unload()
```

## Testing

```
lune run tests/shaders/run.luau
```

Runs Lyra UI and the shaders inside the [LuaU-Mock-Kit](https://github.com/lyraEz/LuaU-Mock-Kit) harness (checked out next to this repository; the path is in `tests/shaders/.luaurc`). It turns every effect on and off, checks the floor reflection (mirrored copies, see-through floor, hidden and trimmed parts, full restore), checks that each wall-mirror reflection lands exactly on the true reflection for hundreds of random surfaces and camera positions, decodes and fits LUT files, clicks through the interface, runs the chat commands and checks that turning the engine off or unloading leaves the game's lighting as it was.
