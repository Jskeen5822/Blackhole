import * as THREE from "https://cdn.jsdelivr.net/npm/three@0.161/build/three.module.js";

const canvas = document.getElementById("blackhole-canvas");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
// Fixed 1080p resolution for 60fps rendering
renderer.setPixelRatio(1);
renderer.setSize(1920, 1080);

const scene = new THREE.Scene();
const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 10);
camera.position.set(0, 0, 1);
camera.lookAt(0, 0, 0);
renderer.setClearColor(0x02030b, 1);

async function loadShader(path) {
  const response = await fetch(path, { cache: "no-store" });
  return response.text();
}

function createFallbackPalette() {
  const data = new Uint8Array([
    5, 3, 12, 255,
    12, 6, 20, 255,
    42, 20, 70, 255,
    160, 120, 200, 255,
  ]);
  const texture = new THREE.DataTexture(data, 2, 2, THREE.RGBAFormat);
  texture.needsUpdate = true;
  texture.minFilter = THREE.LinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.wrapS = texture.wrapT = THREE.ClampToEdgeWrapping;
  if (THREE.SRGBColorSpace) {
    texture.colorSpace = THREE.SRGBColorSpace;
  }
  return texture;
}

function createCombinedPalette(sources) {
  if (sources.length === 0) {
    return null;
  }

  const width = 256;
  const sampleHeight = 256;
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = sampleHeight;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  if (!ctx) {
    return null;
  }
  ctx.imageSmoothingEnabled = true;

  const accum = new Float32Array(width * 3);
  let usableCount = 0;
  const sampleStart = Math.floor(sampleHeight * 0.32);
  const sampleEnd = Math.ceil(sampleHeight * 0.68);
  const sampleRows = Math.max(1, sampleEnd - sampleStart);
  const invRows = 1 / sampleRows;

  sources.forEach((source) => {
    try {
      ctx.clearRect(0, 0, width, sampleHeight);
      ctx.drawImage(source, 0, 0, width, sampleHeight);
      const imageData = ctx.getImageData(0, 0, width, sampleHeight);
      const data = imageData.data;
      for (let x = 0; x < width; x += 1) {
        let r = 0;
        let g = 0;
        let b = 0;
        for (let y = sampleStart; y < sampleEnd; y += 1) {
          const idx = (y * width + x) * 4;
          r += data[idx + 0];
          g += data[idx + 1];
          b += data[idx + 2];
        }
        accum[x * 3 + 0] += (r * invRows) / 255;
        accum[x * 3 + 1] += (g * invRows) / 255;
        accum[x * 3 + 2] += (b * invRows) / 255;
      }
      usableCount += 1;
    } catch (error) {
      console.warn("Unable to read palette image", error);
    }
  });

  if (usableCount === 0) {
    console.warn("Combined palette fallback: no readable sources");
    return null;
  }

  console.info(`Combined palette using ${usableCount} references`);

  const averaged = new Float32Array(width * 3);
  let brightness = 0;
  for (let i = 0; i < width; i += 1) {
    const r = accum[i * 3 + 0] / usableCount;
    const g = accum[i * 3 + 1] / usableCount;
    const b = accum[i * 3 + 2] / usableCount;
    averaged[i * 3 + 0] = r;
    averaged[i * 3 + 1] = g;
    averaged[i * 3 + 2] = b;
    brightness += (r + g + b) / 3;
  }
  brightness /= width;

  const targetBrightness = 0.12;
  let scale = 1.0;
  if (brightness > 1e-4) {
    scale = THREE.MathUtils.clamp(targetBrightness / brightness, 0.75, 4.5);
  } else {
    scale = 2.5;
  }

  const output = new Uint8Array(width * 4);
  for (let i = 0; i < width; i += 1) {
    const r = Math.min(1, averaged[i * 3 + 0] * scale);
    const g = Math.min(1, averaged[i * 3 + 1] * scale);
    const b = Math.min(1, averaged[i * 3 + 2] * scale);
    output[i * 4 + 0] = Math.max(0, Math.min(255, Math.round(r * 255)));
    output[i * 4 + 1] = Math.max(0, Math.min(255, Math.round(g * 255)));
    output[i * 4 + 2] = Math.max(0, Math.min(255, Math.round(b * 255)));
    output[i * 4 + 3] = 255;
  }

  const dataTexture = new THREE.DataTexture(output, width, 1, THREE.RGBAFormat);
  dataTexture.needsUpdate = true;
  dataTexture.minFilter = THREE.LinearFilter;
  dataTexture.magFilter = THREE.LinearFilter;
  dataTexture.wrapS = dataTexture.wrapT = THREE.ClampToEdgeWrapping;
  if (THREE.SRGBColorSpace) {
    dataTexture.colorSpace = THREE.SRGBColorSpace;
  }
  return dataTexture;
}

async function loadImageSource(path) {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${path}`);
  }

  const blob = await response.blob();

  if ("createImageBitmap" in window) {
    const bitmap = await createImageBitmap(blob);
    const cleanup = () => {
      if (bitmap.close) {
        bitmap.close();
      }
    };
    return { source: bitmap, cleanup };
  }

  const objectUrl = URL.createObjectURL(blob);
  const img = new Image();
  img.crossOrigin = "anonymous";

  const source = await new Promise((resolve, reject) => {
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`Failed to load image ${path}`));
    img.src = objectUrl;
  });

  const cleanup = () => {
    URL.revokeObjectURL(objectUrl);
  };

  return { source, cleanup };
}

async function init() {
  const [vertexShader, fragmentShader] = await Promise.all([
    loadShader("shaders/fullscreen.vert.glsl"),
    loadShader("shaders/blackhole_cinematic.frag.glsl"),
  ]);

  console.info("Fragment shader snippet:", fragmentShader.slice(0, 160));

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

  const imageSources = [];
  for (const path of textureCandidates) {
    try {
      const { source, cleanup } = await loadImageSource(path);
      imageSources.push({ source, cleanup, path });
      console.info(`Loaded reference image from ${path}`);
    } catch (error) {
      console.warn(`Unable to load ${path}`, error);
    }
  }

  const combinedPalette = createCombinedPalette(imageSources.map((entry) => entry.source)) || createFallbackPalette();
  imageSources.forEach((entry) => {
    if (entry.cleanup) {
      entry.cleanup();
    }
  });

  const uniforms = {
    u_time: { value: 0 },
    u_cycle: { value: 0 },
    u_elapsed: { value: 0 }, // Continuous time for seamless rotation
    u_resolution: { value: new THREE.Vector2(1920, 1080) },
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

  // Fixed 1080p - no resize handler needed

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
    uniforms.u_elapsed.value = adjusted; // Continuous time for seamless infinite rotation

    renderer.render(scene, camera);
    requestAnimationFrame(animate);
  }

  animate();
}

init();
