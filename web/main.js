import * as THREE from "https://cdn.jsdelivr.net/npm/three@0.161/build/three.module.js";

const canvas = document.getElementById("blackhole-canvas");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);

const scene = new THREE.Scene();
const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 10);
camera.position.set(0, 0, 1);
camera.lookAt(0, 0, 0);
renderer.setClearColor(0x02030b, 1);

async function loadShader(path) {
  const response = await fetch(path);
  return response.text();
}

function loadTexture(loader, path) {
  return new Promise((resolve, reject) => {
    loader.load(path, resolve, undefined, reject);
  });
}

async function init() {
  const [vertexShader, fragmentShader] = await Promise.all([
    loadShader("shaders/fullscreen.vert.glsl"),
    loadShader("shaders/blackhole.frag.glsl"),
  ]);

  const textureLoader = new THREE.TextureLoader();

  const textureCandidates = [
    { label: "Default Palette", path: "assets/textures/blackhole_reference.jpg" },
    { label: "Ref Image 1", path: "assets/textures/Screenshot 2025-11-04 163420.png" },
    { label: "Ref Image 2", path: "assets/textures/Screenshot 2025-11-04 163433.png" },
    { label: "Ref Image 3", path: "assets/textures/Screenshot 2025-11-04 163452.png" },
  ];

  const loadedTextures = [];
  for (const candidate of textureCandidates) {
    try {
      const texture = await loadTexture(textureLoader, candidate.path);
      texture.wrapS = texture.wrapT = THREE.ClampToEdgeWrapping;
      texture.minFilter = THREE.LinearFilter;
      loadedTextures.push({ ...candidate, texture });
      console.info(`Loaded palette texture from ${candidate.path}`);
    } catch (error) {
      console.warn(`Unable to load ${candidate.path}`, error);
    }
  }

  if (loadedTextures.length === 0) {
    console.warn("No reference textures available; using fallback palette");
    const fallbackSize = 4;
    const data = new Uint8Array([
      5, 3, 12,
      12, 6, 20,
      42, 20, 70,
      160, 120, 200,
    ]);
    const fallback = new THREE.DataTexture(data, 2, 2, THREE.RGBFormat);
    fallback.needsUpdate = true;
    loadedTextures.push({ label: "Procedural", path: "fallback", texture: fallback });
  }

  const uniforms = {
    u_time: { value: 0 },
    u_cycle: { value: 0 },
    u_resolution: { value: new THREE.Vector2(window.innerWidth, window.innerHeight) },
    u_baseTexture: { value: loadedTextures[0].texture },
    u_acceleration: { value: 1 },
    u_warp: { value: 0.75 },
    u_jetIntensity: { value: 1.0 },
  };

  const material = new THREE.ShaderMaterial({
    uniforms,
    vertexShader,
    fragmentShader,
    side: THREE.DoubleSide,
  });

  const geometry = new THREE.PlaneGeometry(2, 2);
  const mesh = new THREE.Mesh(geometry, material);
  scene.add(mesh);

  const controls = {
    speed: document.getElementById("speed"),
    warp: document.getElementById("warp"),
    jet: document.getElementById("jet"),
    palette: document.getElementById("palette"),
  };

  controls.palette.innerHTML = "";
  loadedTextures.forEach((candidate, index) => {
    const option = document.createElement("option");
    option.value = String(index);
    option.textContent = candidate.label;
    controls.palette.appendChild(option);
  });
  controls.palette.value = "0";

  controls.speed.addEventListener("input", () => {
    uniforms.u_acceleration.value = parseFloat(controls.speed.value);
  });

  controls.warp.addEventListener("input", () => {
    uniforms.u_warp.value = parseFloat(controls.warp.value);
  });

  controls.jet.addEventListener("input", () => {
    uniforms.u_jetIntensity.value = parseFloat(controls.jet.value);
  });

  controls.palette.addEventListener("change", () => {
    const index = parseInt(controls.palette.value, 10);
    const selected = loadedTextures[index];
    if (selected) {
      uniforms.u_baseTexture.value = selected.texture;
      material.uniforms.u_baseTexture.value = selected.texture;
      console.info(`Switched palette to ${selected.path}`);
    }
  });

  function onResize() {
    const { innerWidth, innerHeight } = window;
    renderer.setSize(innerWidth, innerHeight);
    uniforms.u_resolution.value.set(innerWidth, innerHeight);
  }

  window.addEventListener("resize", onResize);

  const LOOP_DURATION = 18.0; // seconds for a slower seamless cycle
  const clock = new THREE.Clock();

  function animate() {
    const elapsed = clock.getElapsedTime();
    const speed = uniforms.u_acceleration.value;
    const adjusted = elapsed * speed;
    const looped = adjusted % LOOP_DURATION;
    const phase = looped / LOOP_DURATION;
    uniforms.u_cycle.value = phase;
    uniforms.u_time.value = phase * Math.PI * 2.0;

    renderer.render(scene, camera);
    requestAnimationFrame(animate);
  }

  animate();
}

init();
