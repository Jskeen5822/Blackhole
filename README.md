# Blackhole

## Project Scaffold

```
assets/
	input_brainrot/        # Drop your brain-rot images here before running the script
	reference/
config/
	defaults.json          # Animation parameters (mass, spin, camera, render)
output/                  # Rendered frames or final video renders
scripts/
	blackhole_animation.py # Blender entry point (run inside Blender)
shaders/
```

## Usage

1. Copy source images into `assets/input_brainrot` (any `.png/.jpg/.jpeg/.webp/.tiff`).
2. Optionally duplicate `config/defaults.json` and tweak values:
	 - `blackhole.mass`, `blackhole.spin`, `blackhole.radius`
	 - `blackhole.disk_color`, `blackhole.disk_intensity`
	 - `blackhole.ingestion_speed`, `blackhole.stretch_factor`
	 - `camera.path_length`, `camera.focal_length`, `camera.aperture_fstop`
		- `render.frame_start`, `render.frame_end`, `render.output_path`, `render.samples`
3. Launch Blender ≥ 3.6 with Cycles enabled and run:
	 ```powershell
	 blender --background --python scripts/blackhole_animation.py -- config/defaults.json
	 ```
		The script builds the scene, attaches each image to the ingest curve, and keyframes the spaghettification.
	4. For interactive tweaks, open Blender’s Scripting workspace, load `scripts/blackhole_animation.py`, press `Run Script`, then adjust materials/camera before rendering.

## Render Settings

- Output defaults to 4K (3840×2160), 30 fps, MP4/H.264; adjust via `render` config block.
- Motion blur and depth of field are enabled; disable in `Render` tab if needed for previews.
- Use `Render > Render Animation` to bake frames, or run headless CLI render with the same command.

## Swapping Images

- Leave `assets/input_brainrot` empty if you only want the black hole; no ingestion rig will be created.
- After each run a preview still is written to `output/blackhole_preview.png` (set `render.preview_still_path` to null/empty to skip).
- Drop new files into `assets/input_brainrot`, rerun the script; keyframes re-sync automatically.

## Visual Notes

- The accretion disk shader now layers radial temperature gradients with turbulent streaking to mimic relativistic shear.
- A far-side mirage ring is bent upward to emulate lensing; tweak `blackhole.spin` or the `FarDiskBend` modifier in Blender for different wraps.
- The photon ring is a high-intensity caustic with noise-driven flicker to suggest photon trajectories.
- The world background mixes a dark nebula gradient with procedural stars for contrast around the silhouette.
- For incremental updates, re-run after deleting the previous `Brainrot_` objects inside Blender.

## Output

- Final video written to `output/blackhole_anim.mp4` (relative to `.blend` file location).
- Individual frames available in the Blender temp directory if you change file format to `PNG`.

## Reference

- Accretion disk color/lighting loosely based on NASA’s 2019 “Simulation of Material Around a Spinning Black Hole” (Public Domain, https://svs.gsfc.nasa.gov/13216).