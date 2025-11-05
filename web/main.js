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

function createFallbackPalette() {
  const data = new Uint8Array([
    5, 3, 12,
    12, 6, 20,
    42, 20, 70,
    160, 120, 200,
  ]);
  const texture = new THREE.DataTexture(data, 2, 2, THREE.RGBFormat);
  texture.needsUpdate = true;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.wrapS = texture.wrapT = THREE.ClampToEdgeWrapping;
  return texture;
}

function createCombinedPalette(textures) {
  if (textures.length === 0) {
    return null;
  }

  const width = 256;
  const height = 1;
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) {
    return null;
  }
  ctx.imageSmoothingEnabled = true;

  const accum = new Float32Array(width * 3);
  let usableCount = 0;

  textures.forEach((texture) => {
    const image = texture.image;
    if (!image) {
      return;
    }

    try {
      ctx.clearRect(0, 0, width, height);
      ctx.drawImage(image, 0, 0, width, height);
      const imageData = ctx.getImageData(0, 0, width, height);
      const data = imageData.data;
      for (let i = 0; i < width; i += 1) {
        const idx = i * 4;
        accum[i * 3 + 0] += data[idx + 0] / 255;
        accum[i * 3 + 1] += data[idx + 1] / 255;
        accum[i * 3 + 2] += data[idx + 2] / 255;
      }
      usableCount += 1;
    } catch (error) {
      console.warn("Unable to read palette texture", error);
    }
  });

  if (usableCount === 0) {
    return null;
  }

  const output = new Uint8Array(width * 3);
  for (let i = 0; i < width; i += 1) {
    const r = accum[i * 3 + 0] / usableCount;
    const g = accum[i * 3 + 1] / usableCount;
    const b = accum[i * 3 + 2] / usableCount;
    output[i * 3 + 0] = Math.max(0, Math.min(255, Math.round(r * 255)));
    output[i * 3 + 1] = Math.max(0, Math.min(255, Math.round(g * 255)));
    output[i * 3 + 2] = Math.max(0, Math.min(255, Math.round(b * 255)));
  }

  const dataTexture = new THREE.DataTexture(output, width, 1, THREE.RGBFormat);
  dataTexture.needsUpdate = true;
  dataTexture.minFilter = THREE.LinearFilter;
  dataTexture.magFilter = THREE.LinearFilter;
  dataTexture.wrapS = dataTexture.wrapT = THREE.ClampToEdgeWrapping;
  return dataTexture;
}

async function init() {
  const [vertexShader, fragmentShader] = await Promise.all([
    loadShader("shaders/fullscreen.vert.glsl"),
    loadShader("shaders/blackhole.frag.glsl"),
  ]);

  const textureLoader = new THREE.TextureLoader();

  const textureCandidates = [
    "assets/textures/blackhole_reference.jpg",
    "assets/textures/Screenshot 2025-11-04 163420.png",
    "assets/textures/Screenshot 2025-11-04 163433.png",
    "assets/textures/Screenshot 2025-11-04 163452.png",
    "assets/textures/Screenshot 2025-11-04 192334.png",
    "assets/textures/Screenshot 2025-11-04 192344.png",
    "assets/textures/Screenshot 2025-11-04 192354.png",
    "assets/textures/Screenshot 2025-11-04 192405.png",
  ];

  const loadedTextures = [];
  for (const path of textureCandidates) {
    try {
      const texture = await loadTexture(textureLoader, path);
      texture.wrapS = texture.wrapT = THREE.ClampToEdgeWrapping;
      texture.minFilter = THREE.LinearFilter;
      loadedTextures.push(texture);
      console.info(`Loaded palette texture from ${path}`);
    } catch (error) {
      console.warn(`Unable to load ${path}`, error);
    }
  }

  if (loadedTextures.length === 0) {
    console.warn("No reference textures available; using fallback palette");
    const data = new Uint8Array([
      5, 3, 12,
      12, 6, 20,
      42, 20, 70,
      160, 120, 200,
    ]);
    const fallback = new THREE.DataTexture(data, 2, 2, THREE.RGBFormat);
    fallback.needsUpdate = true;
    loadedTextures.push(fallback);
  }

  let combinedPalette = createCombinedPalette(loadedTextures);
  if (!combinedPalette) {
    combinedPalette = createFallbackPalette();
  }

  const uniforms = {
    u_time: { value: 0 },
    u_cycle: { value: 0 },
    u_resolution: { value: new THREE.Vector2(window.innerWidth, window.innerHeight) },
    u_baseTexture: { value: combinedPalette },
    u_acceleration: { value: 1.2 },
    u_warp: { value: 0.85 },
    u_jetIntensity: { value: 1.05 },
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

  function onResize() {
    const { innerWidth, innerHeight } = window;
    renderer.setSize(innerWidth, innerHeight);
    uniforms.u_resolution.value.set(innerWidth, innerHeight);
  }

  window.addEventListener("resize", onResize);

  const LOOP_DURATION = 13.5; // faster seamless cycle for default state
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
