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
| SSR | Real-time reflections of players, you and the world on floors, walls, ceilings and water | Planar mirrors, see below |
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

Rays across the screen find the biggest reflective surfaces in view. Floor tiles on the same level are joined into one surface. Each surface gets a mirror: a thin invisible part lying on it with a SurfaceGui and a ViewportFrame. The ViewportFrame holds copies of the characters and objects nearby, mirrored across the surface, and its camera sits exactly where your camera is, looking straight into the surface. With the camera perpendicular to the surface, the image maps onto the surface with a plain scale and offset, so the ViewportFrame is sized and placed inside the SurfaceGui (an off-axis projection) and the mirrored world lines up with the real one from any angle. Because the mirror is drawn on the surface, anything standing in front of it hides its reflection correctly.

Moving copies (characters, unanchored parts) are updated every frame in one bulk move; still objects are checked a few at a time. Reflection strength follows the material (glass, marble, metal, ceramic and polished plastic reflect most), the viewing angle (Fresnel) and how bright the surface is.

## Limits

Roblox gives scripts no pixel shaders, so these are the honest trade-offs:

- Copies inside reflections use simple directional lighting (no shadows, no point lights, no particles or terrain). Meshes keep their own handedness, so text and asymmetric meshes are not flipped.
- A Roblox camera stops at 120° of view. Looking very low along a long floor, the part of the floor far to the sides may not reflect.
- Reflections need flat surfaces: blocks, flat mesh slabs and terrain water. Round parts, slopes and terrain other than water do not reflect.
- MXAO, Global Illumination and Exposure are built in the world from raycasts, not from the depth buffer. They are approximations of the shader effects with the same names.
- Sharpness raises local contrast; Roblox has no sharpening filter.
- Deband uses an EditableImage when the game allows it, and a light glyph pattern when it does not.
- The lighting technology can only change on executors with `sethiddenproperty`.

## Phones

The engine starts on the Low quality level on phones and tablets, and auto quality (Settings) does less work whenever the frame rate drops below the target. Reflections and MXAO are the heaviest effects; Statistics shows what each one costs.

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

Runs Lyra UI and the shaders inside the [LuaU-Mock-Kit](https://github.com/lyraEz/LuaU-Mock-Kit) harness (checked out next to this repository; the path is in `tests/shaders/.luaurc`). It turns every effect on and off, checks that each reflection lands exactly on the true reflection for hundreds of random surfaces and camera positions, decodes and fits LUT files, clicks through the interface, runs the chat commands and checks that turning the engine off or unloading leaves the game's lighting as it was.
