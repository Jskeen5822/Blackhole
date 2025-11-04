"""Build the black hole scene and render a single preview frame."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

try:
    import bpy  # type: ignore
except ModuleNotFoundError as exc:  # pragma: no cover
    raise SystemExit("Run inside Blender.") from exc


ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = ROOT / "scripts" / "blackhole_animation.py"
CONFIG_PATH = ROOT / "config" / "defaults.json"


def _load_module() -> object:
    spec = importlib.util.spec_from_file_location("blackhole_animation", SCRIPT_PATH)
    if not spec or not spec.loader:
        raise RuntimeError("Unable to load blackhole_animation script")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def main() -> None:
    module = _load_module()
    module.main([str(CONFIG_PATH)])  # type: ignore[attr-defined]

    scene = bpy.context.scene
    scene.frame_set(scene.frame_start)
    scene.render.image_settings.file_format = "PNG"
    output_path = ROOT / "output" / "preview.png"
    scene.render.filepath = str(output_path)

    bpy.ops.render.render(write_still=True)
    print(f"Preview saved to {output_path}")


if __name__ == "__main__":
    main()
