// src/tests/apps/admin/brandSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import { brandDiagnosticsResponseSchema } from '@/schemas/api/internal/responses/colonel-system';

/**
 * Zod tripwire (CONTRACT 3) for the brand-pack diagnostic contract (#3822).
 * GET /api/colonel/system/brand emits the `{ record, details }` envelope this
 * schema wraps; the payloads below are shaped exactly as the diagnostic logic
 * class emits them — a HEALTHY instance, a BROKEN-CHECKOUT instance (every
 * nullable field null), and a MOUNT-RACE instance (both danger booleans set).
 * If the backend response drifts, these fail rather than the contract silently
 * rotting into a neutral-branding blind spot.
 */

// Healthy instance: pack resolved, manifest on disk, no danger flags.
function healthyPayload() {
  return {
    shrimp: '',
    record: {},
    details: {
      home: '/app',
      env: { brand_pack: 'onetimesecret', brand_assets_dir: '/app/etc/branding' },
      config: {
        brand_pack: 'onetimesecret',
        brand_assets_dir: '/app/etc/branding',
        brand_absorbed: ['product_name'],
      },
      roots: [
        { path: '/app/etc/branding', exists: true },
        { path: '/app/public/branding', exists: false },
      ],
      resolved_dir: '/app/etc/branding/onetimesecret',
      fell_back_to_default: false,
      manifest: {
        path: '/app/etc/branding/onetimesecret/brand.yaml',
        exists: true,
        keys_on_disk: ['product_name', 'logo'],
      },
      boot_vs_live_mismatch: false,
      overlay_assets: ['/favicon.svg'],
    },
  };
}

describe('brand-pack diagnostic schema (ticket #3822, CONTRACT 3)', () => {
  it('accepts a healthy diagnostic payload', () => {
    const parsed = brandDiagnosticsResponseSchema.safeParse(healthyPayload());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.details?.resolved_dir).toBe('/app/etc/branding/onetimesecret');
      expect(parsed.data.details?.fell_back_to_default).toBe(false);
      expect(parsed.data.details?.roots).toHaveLength(2);
    }
  });

  it('accepts a broken-checkout payload with every nullable field null', () => {
    const broken = healthyPayload();
    // ENV not reaching the container + nothing resolved + no manifest on disk.
    broken.details.env.brand_pack = null as unknown as string;
    broken.details.env.brand_assets_dir = null as unknown as string;
    broken.details.config.brand_pack = null as unknown as string;
    broken.details.config.brand_assets_dir = null as unknown as string;
    broken.details.resolved_dir = null as unknown as string;
    broken.details.manifest.path = null as unknown as string;
    broken.details.fell_back_to_default = true;

    const parsed = brandDiagnosticsResponseSchema.safeParse(broken);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.details?.resolved_dir).toBeNull();
      expect(parsed.data.details?.manifest.path).toBeNull();
      expect(parsed.data.details?.env.brand_pack).toBeNull();
    }
  });

  it('accepts a mount-race payload (both danger booleans set)', () => {
    const race = healthyPayload();
    race.details.fell_back_to_default = true;
    race.details.boot_vs_live_mismatch = true;
    const parsed = brandDiagnosticsResponseSchema.safeParse(race);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.details?.boot_vs_live_mismatch).toBe(true);
    }
  });

  it('rejects a payload missing the boot_vs_live_mismatch danger flag (drift tripwire)', () => {
    const bad = healthyPayload();
    // @ts-expect-error — deliberately drop the required danger boolean.
    delete bad.details.boot_vs_live_mismatch;
    expect(brandDiagnosticsResponseSchema.safeParse(bad).success).toBe(false);
  });

  it('rejects a root row missing its required exists flag (drift tripwire)', () => {
    const bad = healthyPayload();
    // @ts-expect-error — deliberately drop the required `exists` field.
    delete bad.details.roots[0].exists;
    expect(brandDiagnosticsResponseSchema.safeParse(bad).success).toBe(false);
  });
});
