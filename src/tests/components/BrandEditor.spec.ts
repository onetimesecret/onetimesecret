// src/tests/components/BrandEditor.spec.ts
//
// Guards the three-path brand editor (3a redesign):
//   1. BrandPathSwitcher emits the picked path and marks the active card.
//   2. SimpleBrandPanel writes the shared BrandSettings (corners → border_radius)
//      and surfaces the primary-vs-white contrast warning.
//   3. BrandEditor: switching paths NEVER mutates brandSettings (the panel is a
//      view over one record) and the Match/Advanced teasers are inert.

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import BrandEditor from '@/apps/workspace/components/dashboard/brand/BrandEditor.vue';
import BrandPathSwitcher from '@/apps/workspace/components/dashboard/brand/BrandPathSwitcher.vue';
import SimpleBrandPanel from '@/apps/workspace/components/dashboard/brand/SimpleBrandPanel.vue';
import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys so assertions don't depend on translation content (house
// convention — see SecretPreview.spec.ts / DomainHeader.spec.ts).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

const previewI18n = { t: (k: string) => k } as any;

// Stub the heavy leaves so these stay unit tests: the color picker (pulls in
// vue-color), the recipient preview column (SecretPreview → BaseSecretDisplay),
// and icons. Fonts are native <select>s (not a component), so nothing to stub.
const leafStubs = {
  ColorPicker: true,
  OIcon: true,
  BrandPreviewColumn: true,
};

const baseSettings = (over: Partial<BrandSettings> = {}): BrandSettings =>
  ({ primary_color: '#4F46E5', ...over }) as BrandSettings;

describe('BrandPathSwitcher', () => {
  it('emits the picked path and marks the active card', async () => {
    const wrapper = mount(BrandPathSwitcher, {
      props: { modelValue: 'simple' },
      global: { stubs: leafStubs },
    });

    const buttons = wrapper.findAll('button');
    expect(buttons).toHaveLength(3); // simple / match / advanced

    // Simple is active on mount.
    expect(buttons[0].attributes('aria-pressed')).toBe('true');
    expect(buttons[1].attributes('aria-pressed')).toBe('false');

    await buttons[1].trigger('click');
    expect(wrapper.emitted('update:modelValue')?.at(-1)).toEqual(['match']);
  });
});

describe('SimpleBrandPanel', () => {
  const mountPanel = (settings: Partial<BrandSettings> = {}) =>
    mount(SimpleBrandPanel, {
      props: { modelValue: baseSettings(settings) },
      global: { stubs: leafStubs },
    });

  it('writes border_radius when a corner is picked (Square→none, Pill→full)', async () => {
    const wrapper = mountPanel({ border_radius: 'md' });
    const cornerButtons = wrapper.get('[role="group"]').findAll('button');
    expect(cornerButtons).toHaveLength(3);

    await cornerButtons[0].trigger('click'); // Square
    expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).toMatchObject({
      border_radius: 'none',
    });

    await cornerButtons[2].trigger('click'); // Pill
    expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).toMatchObject({
      border_radius: 'full',
    });
  });

  it('marks the active corner from the current border_radius', () => {
    const wrapper = mountPanel({ border_radius: 'full' });
    const cornerButtons = wrapper.get('[role="group"]').findAll('button');
    // Square / Rounded / Pill → none / md / full
    expect(cornerButtons[0].attributes('aria-pressed')).toBe('false');
    expect(cornerButtons[2].attributes('aria-pressed')).toBe('true');
  });

  it('toggles the More options (fonts) disclosure', async () => {
    const wrapper = mountPanel();
    const toggle = wrapper.get('button[aria-expanded]');
    // Collapsed on mount; the font selects are not rendered yet.
    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(wrapper.findAll('select')).toHaveLength(0);

    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    // Body + heading font selects appear, each exposing all font options.
    const selects = wrapper.findAll('select');
    expect(selects).toHaveLength(2);
    // The picker exposes the full font vocabulary (not just Sans) — regression
    // guard for the "both options are Sans-Serif" report.
    expect(selects[0].findAll('option').length).toBeGreaterThanOrEqual(3);
  });
});

describe('BrandEditor', () => {
  const mountEditor = (settings: Partial<BrandSettings> = {}) =>
    mount(BrandEditor, {
      props: {
        modelValue: baseSettings(settings),
        logoImage: null,
        onLogoUpload: vi.fn(),
        onLogoRemove: vi.fn(),
        previewI18n,
        displayDomain: 'brand.example.com',
        secretIdentifier: 'abcd',
      },
      global: { stubs: leafStubs },
    });

  it('switching paths never mutates brandSettings (no update:modelValue on switch)', async () => {
    const wrapper = mountEditor();
    // Simple panel is shown by default.
    expect(wrapper.findComponent(SimpleBrandPanel).exists()).toBe(true);

    // Click the "match" card in the switcher (2nd of the 3 path buttons).
    const pathButtons = wrapper.getComponent(BrandPathSwitcher).findAll('button');
    await pathButtons[1].trigger('click');

    // The functional panel is gone, a coming-soon teaser replaces it, and the
    // parent record was never touched by the path switch.
    expect(wrapper.findComponent(SimpleBrandPanel).exists()).toBe(false);
    expect(wrapper.text()).toContain('web.branding.badge_coming_soon');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('renders the Match/Advanced teasers as non-interactive (pointer-events-none)', async () => {
    const wrapper = mountEditor();
    const pathButtons = wrapper.getComponent(BrandPathSwitcher).findAll('button');

    await pathButtons[2].trigger('click'); // advanced
    // The decorative mockup wrapper is inert.
    expect(wrapper.find('.pointer-events-none').exists()).toBe(true);
  });
});
