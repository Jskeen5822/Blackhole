"""Black hole ingestion animation for Blender (Cycles).

Run inside Blender:
    blender --background --python scripts/blackhole_animation.py -- config/defaults.json
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

try:
    import bpy
    import mathutils
except ModuleNotFoundError as exc:  # pragma: no cover - Blender-only module
    raise SystemExit("Execute this script inside Blender's Python runtime.") from exc


PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _resolve_project_path(path_str: str) -> Path:
    if not path_str:
        return PROJECT_ROOT
    normalized = path_str
    if normalized.startswith("//"):
        normalized = normalized[2:]
    candidate = Path(normalized)
    if not candidate.is_absolute():
        candidate = (PROJECT_ROOT / candidate).resolve()
    return candidate


# ---------------------------------------------------------------------------
# Data containers


@dataclass(slots=True)
class BlackHoleSettings:
    mass: float = 5.0  # relative units, drives disk size/thickness
    spin: float = 0.7  # 0..0.998 (Kerr limit approx)
    radius: float = 8.0  # event horizon radius in Blender units
    disk_color: tuple[float, float, float] = (1.0, 0.45, 0.1)
    disk_intensity: float = 6.0
    ingestion_speed: float = 1.0
    stretch_factor: float = 3.0


@dataclass(slots=True)
class CameraSettings:
    path_length: int = 360
    focal_length: float = 55.0
    depth_of_field: bool = True
    aperture_fstop: float = 2.2


@dataclass(slots=True)
class RenderSettings:
    resolution_x: int = 3840
    resolution_y: int = 2160
    frame_rate: int = 30
    frame_start: int = 1
    frame_end: int = 450
    output_path: str = "//output/blackhole_anim.mp4"
    samples: int = 1024
    preview_still_path: Optional[str] = "//output/blackhole_preview.png"


# ---------------------------------------------------------------------------
# Core domain objects


class BlackHole:
    def __init__(self, settings: BlackHoleSettings) -> None:
        self.settings = settings
        self.collection = self._ensure_collection("BlackHole_System")

    def build(self) -> None:
        event_horizon = self._create_event_horizon()
        photon_ring = self._create_photon_ring()
        disk = self._create_accretion_disk()
        lens = self._create_gravitational_lens()

        for obj in (event_horizon, photon_ring, disk, lens):
            self.collection.objects.link(obj)

    def _create_event_horizon(self) -> bpy.types.Object:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, radius=self.settings.radius)
        sphere = bpy.context.active_object
        sphere.name = "BH_EventHorizon"
        sphere.data.materials.clear()
        mat = self._ensure_material("BH_EventHorizon_MAT")
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        emission = nodes.new("ShaderNodeEmission")
        emission.inputs[0].default_value = (0.01, 0.01, 0.01, 1.0)
        emission.inputs[1].default_value = 0.02
        links.new(emission.outputs[0], output.inputs[0])
        sphere.data.materials.append(mat)
        return sphere

    def _create_photon_ring(self) -> bpy.types.Object:
        bpy.ops.mesh.primitive_torus_add(
            major_radius=self.settings.radius * 1.15,
            minor_radius=self.settings.radius * 0.12,
            major_segments=256,
            minor_segments=32,
        )
        torus = bpy.context.active_object
        torus.name = "BH_PhotonRing"
        mat = self._ensure_material("BH_PhotonRing_MAT")
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        emission = nodes.new("ShaderNodeEmission")
        emission.inputs[1].default_value = 15.0
        color_ramp = nodes.new("ShaderNodeValToRGB")
        color_ramp.color_ramp.interpolation = "EASE"
        color_ramp.color_ramp.elements[0].position = 0.2
        color_ramp.color_ramp.elements[0].color = (*self.settings.disk_color, 1.0)
        color_ramp.color_ramp.elements[1].position = 1.0
        color_ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
        texture = nodes.new("ShaderNodeTexNoise")
        texture.inputs[1].default_value = 20.0
        texture.inputs[2].default_value = 0.3
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs[3].default_value[2] = self.settings.spin * 5.0
        tex_coord = nodes.new("ShaderNodeTexCoord")
        links.new(tex_coord.outputs["Object"], mapping.inputs[0])
        links.new(mapping.outputs[0], texture.inputs[0])
        links.new(texture.outputs[1], color_ramp.inputs[0])
        links.new(color_ramp.outputs[0], emission.inputs[0])
        links.new(emission.outputs[0], output.inputs[0])
        torus.data.materials.clear()
        torus.data.materials.append(mat)
        return torus

    def _create_accretion_disk(self) -> bpy.types.Object:
        bpy.ops.mesh.primitive_cylinder_add(radius=self.settings.radius * 3.0, depth=self.settings.radius * 0.1)
        disk = bpy.context.active_object
        disk.name = "BH_AccretionDisk"
        disk.location.z = 0.0
        disk.scale.z = 0.1
        mat = self._ensure_material("BH_AccretionDisk_MAT")
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        emission = nodes.new("ShaderNodeEmission")
        emission.inputs[1].default_value = self.settings.disk_intensity
        color_ramp = nodes.new("ShaderNodeValToRGB")
        color_ramp.color_ramp.elements[0].position = 0.0
        color_ramp.color_ramp.elements[0].color = (0.05, 0.05, 0.05, 1.0)
        color_ramp.color_ramp.elements[1].position = 0.4
        color_ramp.color_ramp.elements[1].color = (*self.settings.disk_color, 1.0)
        color_ramp.color_ramp.elements.new(0.8)
        color_ramp.color_ramp.elements[2].color = (1.0, 0.95, 0.7, 1.0)
        gradient = nodes.new("ShaderNodeTexGradient")
        gradient.gradient_type = "QUADRATIC"
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs[3].default_value[2] = self.settings.spin * 2.5
        tex_coord = nodes.new("ShaderNodeTexCoord")
        links.new(tex_coord.outputs["Object"], mapping.inputs[0])
        links.new(mapping.outputs[0], gradient.inputs[0])
        links.new(gradient.outputs[0], color_ramp.inputs[0])
        links.new(color_ramp.outputs[0], emission.inputs[0])
        links.new(emission.outputs[0], output.inputs[0])
        disk.data.materials.clear()
        disk.data.materials.append(mat)
        return disk

    def _create_gravitational_lens(self) -> bpy.types.Object:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, radius=self.settings.radius * 2.4)
        lens = bpy.context.active_object
        lens.name = "BH_LensingShell"
        lens.display_type = "WIRE"
        lens.data.materials.clear()
        mat = self._ensure_material("BH_LensingShell_MAT")
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        emission = nodes.new("ShaderNodeEmission")
        emission.inputs[0].default_value = (0.2, 0.3, 0.45, 1.0)
        emission.inputs[1].default_value = 0.15
        transparent = nodes.new("ShaderNodeBsdfTransparent")
        mix = nodes.new("ShaderNodeMixShader")
        fresnel = nodes.new("ShaderNodeFresnel")
        fresnel.inputs[0].default_value = 1.45
        links.new(fresnel.outputs[0], mix.inputs[0])
        links.new(transparent.outputs[0], mix.inputs[1])
        links.new(emission.outputs[0], mix.inputs[2])
        links.new(mix.outputs[0], output.inputs[0])
        lens.data.materials.append(mat)
        lens.cycles.is_portal = True
        return lens

    @staticmethod
    def _ensure_collection(name: str) -> bpy.types.Collection:
        if name in bpy.data.collections:
            return bpy.data.collections[name]
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
        return coll

    @staticmethod
    def _ensure_material(name: str) -> bpy.types.Material:
        if name in bpy.data.materials:
            return bpy.data.materials[name]
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        return mat


class CameraPath:
    def __init__(
        self,
        settings: CameraSettings,
        frame_start: int,
        frame_end: int,
        orbit_radius: float,
    ) -> None:
        self.settings = settings
        self.frame_start = frame_start
        self.frame_end = frame_end
        self.orbit_radius = orbit_radius
        self.collection = BlackHole._ensure_collection("Camera_Rig")

    def build(self) -> bpy.types.Object:
        path = self._create_path()
        camera = self._create_camera()
        self._animate_path(camera, path)
        return camera

    def _create_path(self) -> bpy.types.Object:
        bpy.ops.curve.primitive_bezier_circle_add(radius=self.orbit_radius)
        curve = bpy.context.active_object
        curve.name = "CameraOrbit"
        curve.data.resolution_u = 64
        curve.data.use_path = True
        curve.data.path_duration = self.settings.path_length
        self.collection.objects.link(curve)
        return curve

    def _create_camera(self) -> bpy.types.Object:
        if not bpy.data.cameras:
            bpy.ops.object.camera_add()
        else:
            bpy.ops.object.camera_add()
        camera = bpy.context.active_object
        camera.name = "BlackHoleCamera"
        cam_data = camera.data
        cam_data.lens = self.settings.focal_length
        if self.settings.depth_of_field:
            cam_data.dof.use_dof = True
            cam_data.dof.focus_distance = self.orbit_radius * 1.1
            cam_data.dof.aperture_fstop = self.settings.aperture_fstop
        self.collection.objects.link(camera)
        bpy.context.scene.camera = camera
        return camera

    def _animate_path(self, camera: bpy.types.Object, path: bpy.types.Object) -> None:
        constraint = camera.constraints.new("FOLLOW_PATH")
        constraint.target = path
        constraint.use_fixed_location = True
        constraint.forward_axis = "FORWARD_Y"
        constraint.up_axis = "UP_Z"

        track_to = camera.constraints.new(type="TRACK_TO")
        track_to.target = self._target_empty()
        track_to.track_axis = "TRACK_NEGATIVE_Z"
        track_to.up_axis = "UP_Y"

        camera.location.z = self.orbit_radius * 0.25

        constraint.offset_factor = 0.0
        constraint.keyframe_insert(data_path="offset_factor", frame=self.frame_start)
        constraint.offset_factor = 1.0
        constraint.keyframe_insert(data_path="offset_factor", frame=self.frame_end)

    def _target_empty(self) -> bpy.types.Object:
        target_name = "CameraTarget"
        target = bpy.data.objects.get(target_name)
        if target is None:
            bpy.ops.object.empty_add(type="PLAIN_AXES")
            target = bpy.context.active_object
            target.name = target_name
            target.location = (0.0, 0.0, 0.0)
            self.collection.objects.link(target)
        return target


class IngestedImage:
    def __init__(
        self,
        image_path: Path,
        index: int,
        total: int,
        settings: BlackHoleSettings,
        frame_start: int,
        frame_end: int,
        ingest_curve: bpy.types.Object,
        collection: bpy.types.Collection,
    ) -> None:
        self.image_path = image_path
        self.index = index
        self.total = total
        self.settings = settings
        self.frame_start = frame_start
        self.frame_end = frame_end
        self.ingest_curve = ingest_curve
        self.collection = collection

    def build(self) -> bpy.types.Object:
        plane = self._create_image_plane()
        self._attach_to_curve(plane)
        self._animate(plane)
        return plane

    def _create_image_plane(self) -> bpy.types.Object:
        if self.image_path.exists():
            bpy.ops.preferences.addon_enable(module="io_import_images_as_planes")
            prev_objs = set(bpy.context.scene.objects)
            bpy.ops.import_image.to_plane(
                files=[{"name": self.image_path.name}],
                directory=str(self.image_path.parent),
                align_axis="Z+",
                shader="EMISSION",
                relative=False,
            )
            new_objs = [obj for obj in bpy.context.scene.objects if obj not in prev_objs]
            plane = new_objs[0]
        else:
            bpy.ops.mesh.primitive_plane_add(size=2.0)
            plane = bpy.context.active_object
            plane.name = f"Brainrot_{self.image_path.stem}_Placeholder"
            mat = BlackHole._ensure_material("BrainrotPlaceholder_MAT")
            nodes = mat.node_tree.nodes
            links = mat.node_tree.links
            nodes.clear()
            output = nodes.new("ShaderNodeOutputMaterial")
            emission = nodes.new("ShaderNodeEmission")
            emission.inputs[0].default_value = (random.random(), random.random(), random.random(), 1.0)
            emission.inputs[1].default_value = 3.0
            links.new(emission.outputs[0], output.inputs[0])
            plane.data.materials.clear()
            plane.data.materials.append(mat)

        plane.name = f"Brainrot_{self.image_path.stem}"
        plane.scale *= 1.2
        mat = plane.active_material
        if mat and mat.node_tree:
            emission = mat.node_tree.nodes.get("Emission")
            if emission:
                emission.inputs[1].default_value = 3.5
        self.collection.objects.link(plane)
        return plane

    def _attach_to_curve(self, plane: bpy.types.Object) -> None:
        constraint = plane.constraints.new("FOLLOW_PATH")
        constraint.target = self.ingest_curve
        constraint.forward_axis = "FORWARD_Y"
        constraint.up_axis = "UP_Z"
        constraint.use_curve_follow = True
        constraint.use_fixed_location = True
        constraint.offset_factor = 0.0

        curve_modifier = plane.modifiers.new("SpiralWrap", type="CURVE")
        curve_modifier.object = self.ingest_curve

        twist = plane.modifiers.new("Twist", type="SIMPLE_DEFORM")
        twist.deform_method = "TWIST"
        twist.origin = None
        twist.angle = 0.0

        stretch = plane.modifiers.new("Stretch", type="SIMPLE_DEFORM")
        stretch.deform_method = "STRETCH"
        stretch.factor = 0.0
        stretch.origin = None

        plane["twist_mod"] = twist.name
        plane["stretch_mod"] = stretch.name

    def _animate(self, plane: bpy.types.Object) -> None:
        constraint = next((c for c in plane.constraints if c.type == "FOLLOW_PATH"), None)
        twist = plane.modifiers.get(plane.get("twist_mod"))
        stretch = plane.modifiers.get(plane.get("stretch_mod"))
        if not constraint or not twist or not stretch:
            return

        launch_frame = self.frame_start + int((self.index / max(self.total, 1)) * 60)
        arrival_frame = int(self.frame_end * self.settings.ingestion_speed)

        constraint.offset_factor = 0.0
        constraint.keyframe_insert(data_path="offset_factor", frame=launch_frame)
        constraint.offset_factor = 1.0
        constraint.keyframe_insert(data_path="offset_factor", frame=arrival_frame)

        planned_stretch = 1.0 + self.settings.stretch_factor * 3.5
        stretch.factor = 0.0
        stretch.keyframe_insert(data_path="factor", frame=launch_frame)
        stretch.factor = planned_stretch
        stretch.keyframe_insert(data_path="factor", frame=arrival_frame)

        twist.angle = 0.0
        twist.keyframe_insert(data_path="angle", frame=launch_frame)
        twist.angle = math.radians(360.0 * self.settings.spin * 2.0)
        twist.keyframe_insert(data_path="angle", frame=arrival_frame)

        plane.scale = mathutils.Vector((1.0, 1.0, 1.0))
        plane.keyframe_insert(data_path="scale", frame=launch_frame)
        plane.scale = mathutils.Vector((0.2, 4.0 * self.settings.stretch_factor, 0.2))
        plane.keyframe_insert(data_path="scale", frame=arrival_frame)


class ImageIngestor:
    def __init__(
        self,
        settings: BlackHoleSettings,
        frame_start: int,
        frame_end: int,
        radius: float,
    ) -> None:
        self.settings = settings
        self.frame_start = frame_start
        self.frame_end = frame_end
        self.radius = radius
        self.collection = BlackHole._ensure_collection("Brainrot_Images")
        self.ingest_curve = self._create_ingest_curve()

    def load(self, image_paths: Iterable[Path]) -> List[bpy.types.Object]:
        objects = []
        paths = list(image_paths)
        for idx, path in enumerate(paths):
            ingested = IngestedImage(
                image_path=path,
                index=idx,
                total=len(paths),
                settings=self.settings,
                frame_start=self.frame_start,
                frame_end=self.frame_end,
                ingest_curve=self.ingest_curve,
                collection=self.collection,
            )
            objects.append(ingested.build())
        return objects

    def _create_ingest_curve(self) -> bpy.types.Object:
        bpy.ops.curve.primitive_bezier_curve_add()
        curve = bpy.context.active_object
        curve.name = "Brainrot_Ingest_Path"
        spline = curve.data.splines[0]
        spline.bezier_points[0].co = mathutils.Vector((self.radius * 3.5, 0.0, self.radius * 0.5))
        spline.bezier_points[0].handle_right = spline.bezier_points[0].co + mathutils.Vector((-self.radius, self.radius * 0.2, 0.0))
        spline.bezier_points[1].co = mathutils.Vector((0.0, 0.0, 0.0))
        spline.bezier_points[1].handle_left = spline.bezier_points[1].co + mathutils.Vector((self.radius * 0.2, -self.radius * 0.3, 0.0))
        spline.use_cyclic_u = False
        curve.data.resolution_u = 64
        curve.data.use_path = True
        curve.data.path_duration = int(self.settings.ingestion_speed * 200)
        self.collection.objects.link(curve)
        return curve


# ---------------------------------------------------------------------------
# Scene controller


class BlackHoleScene:
    def __init__(
        self,
        bh_settings: BlackHoleSettings,
        cam_settings: CameraSettings,
        render_settings: RenderSettings,
        image_paths: Iterable[Path],
    ) -> None:
        self.bh_settings = bh_settings
        self.cam_settings = cam_settings
        self.render_settings = render_settings
        self.image_paths = list(image_paths)

    def build(self) -> None:
        self._clear_scene()
        self._configure_render()
        self._set_world()
        blackhole = BlackHole(self.bh_settings)
        blackhole.build()
        camera_rig = CameraPath(
            settings=self.cam_settings,
            frame_start=self.render_settings.frame_start,
            frame_end=self.render_settings.frame_end,
            orbit_radius=self.bh_settings.radius * 6.0,
        )
        camera_rig.build()

        if self.image_paths:
            ingestor = ImageIngestor(
                settings=self.bh_settings,
                frame_start=self.render_settings.frame_start,
                frame_end=self.render_settings.frame_end,
                radius=self.bh_settings.radius,
            )
            ingestor.load(self.image_paths)

        self._render_preview_if_requested()

    @staticmethod
    def _clear_scene() -> None:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()
        for block in bpy.data.meshes:
            if block.users == 0:
                bpy.data.meshes.remove(block)

    def _configure_render(self) -> None:
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "GPU" if bpy.context.preferences.addons.get("cycles") else "CPU"
        scene.cycles.samples = self.render_settings.samples
        scene.cycles.use_denoising = True
        scene.render.resolution_x = self.render_settings.resolution_x
        scene.render.resolution_y = self.render_settings.resolution_y
        scene.render.fps = self.render_settings.frame_rate
        scene.frame_start = self.render_settings.frame_start
        scene.frame_end = self.render_settings.frame_end
        output_path = _resolve_project_path(self.render_settings.output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(output_path)
        scene.render.image_settings.file_format = "FFMPEG"
        scene.render.ffmpeg.format = "MPEG4"
        scene.render.ffmpeg.codec = "H264"
        scene.render.ffmpeg.constant_rate_factor = "HIGH"
        scene.render.use_motion_blur = True
        scene.render.motion_blur_shutter = 0.5

    def _set_world(self) -> None:
        world = bpy.context.scene.world
        if world is None:
            world = bpy.data.worlds.new("BlackholeWorld")
            bpy.context.scene.world = world
        world.use_nodes = True
        nodes = world.node_tree.nodes
        links = world.node_tree.links
        nodes.clear()
        background = nodes.new("ShaderNodeBackground")
        background.inputs[0].default_value = (0.02, 0.02, 0.05, 1.0)
        background.inputs[1].default_value = 0.3
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs[1].default_value = 5.0
        color_ramp = nodes.new("ShaderNodeValToRGB")
        color_ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
        color_ramp.color_ramp.elements[1].color = (0.4, 0.4, 0.6, 1.0)
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs[3].default_value[2] = 0.5
        tex_coord = nodes.new("ShaderNodeTexCoord")
        output = nodes.new("ShaderNodeOutputWorld")
        links.new(tex_coord.outputs["Generated"], mapping.inputs[0])
        links.new(mapping.outputs[0], noise.inputs[0])
        links.new(noise.outputs[1], color_ramp.inputs[0])
        links.new(color_ramp.outputs[0], background.inputs[0])
        links.new(background.outputs[0], output.inputs[0])

    def _render_preview_if_requested(self) -> None:
        path = self.render_settings.preview_still_path
        if not path:
            return
        scene = bpy.context.scene
        original_format = scene.render.image_settings.file_format
        original_filepath = scene.render.filepath
        scene.render.image_settings.color_depth = "8"
        scene.render.image_settings.color_mode = "RGB"
        absolute_path = _resolve_project_path(path)
        absolute_path.parent.mkdir(parents=True, exist_ok=True)
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = str(absolute_path)
        bpy.ops.render.render(write_still=True)
        scene.render.filepath = original_filepath
        scene.render.image_settings.file_format = original_format


# ---------------------------------------------------------------------------
# Entry point


def _load_config(config_path: Optional[Path]) -> Dict[str, Any]:
    if config_path and config_path.exists():
        with config_path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    return {}


def _parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    if argv is None:
        if "--" in sys.argv:
            arg_index = sys.argv.index("--") + 1
            argv = sys.argv[arg_index:]
        else:
            argv = []

    parser = argparse.ArgumentParser(description="Black hole animation controller")
    parser.add_argument(
        "config",
        nargs="?",
        help="Optional path to JSON configuration file overriding defaults",
    )
    return parser.parse_args(list(argv))


def _collect_images(image_dir: Path) -> List[Path]:
    valid_suffixes = {".png", ".jpg", ".jpeg", ".webp", ".tiff"}
    if not image_dir.exists():
        return []
    return sorted(
        path for path in image_dir.glob("**/*") if path.suffix.lower() in valid_suffixes
    )


def main(argv: Optional[Iterable[str]] = None) -> None:
    args = _parse_args(argv)
    config_path = Path(args.config).resolve() if args.config else None
    config = _load_config(config_path) if config_path else {}

    bh_settings = BlackHoleSettings(**config.get("blackhole", {}))
    cam_settings = CameraSettings(**config.get("camera", {}))
    render_settings = RenderSettings(**config.get("render", {}))

    image_dir = Path(config.get("images_dir", "../assets/input_brainrot")).resolve()
    image_paths = _collect_images(image_dir)

    scene = BlackHoleScene(bh_settings, cam_settings, render_settings, image_paths)
    scene.build()


if __name__ == "__main__":
    main()
