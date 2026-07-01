// scripts/branding/preset-loader.mjs
//
// Loads a named branding preset (scripts/branding/presets/<name>.mjs) and
// applies its MARK_* values as process.env *defaults*, so the shared generator
// (generate-favicons.mjs) can produce that pack. Kept separate from the
// generator so the validation logic is unit-testable (mark.test.mjs) without
// running the sharp rasterizer.

import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Every MARK_* env var the generator + mark.mjs actually read. A preset key
// outside this set is almost certainly a typo (e.g. MARK_PRIMARY_COLOUR with a
// British "U"), so we warn and skip it rather than silently setting an env var
// nothing consumes.
export const KNOWN_MARK_KEYS = new Set([
  'MARK_PATH',
  'MARK_NATIVE_WIDTH',
  'MARK_NATIVE_HEIGHT',
  'MARK_PRIMARY_COLOR',
  'MARK_BACKGROUND_COLOR',
  'MARK_OG_GRADIENT_DARK',
  'MARK_PRODUCT_NAME',
  'MARK_SHORT_NAME',
  'MARK_ATTRIBUTION',
  'MARK_COVERAGE',
  'MARK_MASK_COVERAGE',
  'MARK_OG_COVERAGE',
  'MARK_OUT_PUBLIC_DIR',
  'MARK_OUT_SRC_DIR',
]);

// A preset name indexes a file path, so restrict it to a safe, traversal-proof
// character set — otherwise MARK_PRESET=../../foo could import arbitrary local
// modules (and execute them) via the dynamic import below.
const PRESET_NAME_RE = /^[a-z0-9-]+$/i;

export function validatePresetName(name) {
  if (typeof name !== 'string' || !PRESET_NAME_RE.test(name)) {
    throw new Error(
      `Invalid preset name '${name}': only letters, digits, and hyphens are allowed.`
    );
  }
  return name;
}

// Applies a preset's values as env defaults — an explicit env var always wins,
// so `MARK_PRIMARY_COLOR=… pnpm run gen:favicons:maruhi` overrides the preset.
// Returns { applied, skipped } for logging/tests. `env` and `importer` are
// injectable so unit tests can exercise validation without the filesystem.
export async function applyPreset(name, { env = process.env, importer } = {}) {
  validatePresetName(name);

  const load =
    importer ||
    ((n) => import(pathToFileURL(resolve(__dirname, 'presets', `${n}.mjs`)).href));

  let mod;
  try {
    mod = await load(name);
  } catch (err) {
    throw new Error(
      `Could not load preset '${name}' (expected scripts/branding/presets/${name}.mjs): ${err.message}`
    );
  }

  const preset = mod && mod.default;
  if (preset === null || typeof preset !== 'object' || Array.isArray(preset)) {
    throw new Error(
      `Preset '${name}' must default-export a plain object of MARK_* overrides.`
    );
  }

  const applied = [];
  const skipped = [];
  for (const [key, value] of Object.entries(preset)) {
    if (!KNOWN_MARK_KEYS.has(key)) {
      skipped.push(key);
      continue;
    }
    if (env[key] === undefined) {
      env[key] = String(value);
      applied.push(key);
    }
  }
  return { applied, skipped };
}
