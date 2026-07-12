// src/tests/components/SecretPreview.spec.ts
//
// Regression guard for the #3646 preview-fidelity fix.
//
// The finding: border_radius rounded the action button ALONE (via an inline
// style), while the logo box, content box and textarea kept following the
// legacy corner_style — so the editor preview diverged from the real recipient
// page, where identityStore.cornerClass -> `rounded-brand` rounds every surface.
//
// The fix mirrors identityStore.cornerClass but scopes `--radius-brand` locally
// (the preview renders an arbitrary edited domain, not the operator's injected
// <html> theme). These tests assert the DOM wiring: the root carries the local
// var and every corner surface carries `rounded-brand`.

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import SecretPreview from '@/apps/workspace/components/dashboard/SecretPreview.vue';
import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys so assertions don't depend on translation content.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

const previewI18n = { t: (k: string) => k } as any;

const mountPreview = (branding: Partial<BrandSettings>) =>
  mount(SecretPreview, {
    props: {
      domainBranding: branding as BrandSettings,
      logoImage: null,
      onLogoUpload: vi.fn(),
      onLogoRemove: vi.fn(),
      secretIdentifier: 'abc123',
      previewI18n,
    },
    global: { stubs: { OIcon: true, ImageUploadModal: true } },
  });

// The always-present action button, keyed by its stable aria wiring.
const actionButton = (wrapper: ReturnType<typeof mountPreview>) =>
  wrapper.get('button[aria-controls="secretContent"]');

describe('SecretPreview border_radius fidelity (#3646)', () => {
  it('rounds every surface via rounded-brand + a locally-scoped --radius-brand when border_radius is set', () => {
    const wrapper = mountPreview({
      primary_color: '#4F46E5',
      corner_style: 'square', // deliberately different from the radius
      border_radius: 'xl', // -> 1rem
      button_text_light: true,
    });

    // The edited domain's radius is scoped to the preview root, so every
    // descendant's `rounded-brand` resolves to THIS domain (not the operator's).
    // (Read the serialized style: jsdom's CSSOM doesn't surface custom
    // properties via getPropertyValue, but they render into the style attr.)
    expect(wrapper.html()).toContain('--radius-brand: 1rem');

    // More than one surface rounds together — the whole point of the fix.
    expect(wrapper.findAll('.rounded-brand').length).toBeGreaterThan(1);

    // The button is among them, and no longer carries a button-only inline radius.
    const button = actionButton(wrapper);
    expect(button.classes()).toContain('rounded-brand');
    expect(button.attributes('style') ?? '').not.toContain('border-radius');

    // corner_style must not leak through when border_radius supersedes it.
    expect(wrapper.find('.rounded-none').exists()).toBe(false);
  });

  it('accepts a numeric px radius', () => {
    const wrapper = mountPreview({ border_radius: 24, corner_style: 'square' });
    expect(wrapper.html()).toContain('--radius-brand: 24px');
    expect(actionButton(wrapper).classes()).toContain('rounded-brand');
    expect(wrapper.find('.rounded-none').exists()).toBe(false);
  });

  it('falls back to corner_style (and sets no --radius-brand) when border_radius is unset', () => {
    const wrapper = mountPreview({ corner_style: 'square' });
    expect(wrapper.html()).not.toContain('--radius-brand');
    expect(wrapper.find('.rounded-brand').exists()).toBe(false);
    expect(wrapper.find('.rounded-none').exists()).toBe(true);
  });

  // Guards the attrs-fallthrough coupling flagged in PR #3694 review: rootStyle
  // is applied to <BaseSecretDisplay> and only reaches every `rounded-brand`
  // descendant because that component stays single-root with inheritAttrs:true.
  // A future refactor making it multi-root (or inheritAttrs:false) would silently
  // drop --radius-brand off the root and desync the preview from the recipient
  // page. Asserting the var lands on wrapper.element (the merged root) trips that.
  it('merges --radius-brand onto the single root element (attrs fallthrough)', () => {
    const wrapper = mountPreview({ border_radius: 'xl' });
    // The var must sit on the ROOT opening tag — i.e. rootStyle fell through onto
    // BaseSecretDisplay's single root, scoping it above every rounded-brand
    // descendant. (jsdom reflects custom props into outerHTML but not into
    // getAttribute('style'), so read the serialized root tag.)
    // First element opening tag (regex skips any leading comment node).
    const rootTag = wrapper.html().match(/<[a-zA-Z][^>]*>/)?.[0] ?? '';
    expect(rootTag).toContain('--radius-brand: 1rem');
  });
});

// BaseSecretDisplay's h2 must carry the heading font token verbatim — any
// body-font fallback inside the display component re-implements the heading
// ladder (heading_font backfilled by font_family) and silently drops
// heading_font when a binding goes missing, which shipped body-font mastheads.
describe('SecretPreview heading font token', () => {
  it('puts the heading token — not the body token — on the h2 when they differ', () => {
    const wrapper = mountPreview({
      font_family: 'sans',
      heading_font: 'slab',
    });

    const heading = wrapper.get('h2');
    expect(heading.classes()).toContain('font-brand-slab');
    // Body font `sans` resolves to font-brand-sans; assert it did NOT leak onto
    // the heading (the ladder must keep heading_font distinct from font_family).
    expect(heading.classes()).not.toContain('font-brand-sans');
  });
});
