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
import DeliveryPanel from '@/apps/workspace/components/dashboard/DeliveryPanel.vue';
import SimpleBrandPanel from '@/apps/workspace/components/dashboard/brand/SimpleBrandPanel.vue';
import type { BrandSettings } from '@/schemas/shapes/v3/custom-domain';

// Echo i18n keys so assertions don't depend on translation content (house
// convention — see SecretPreview.spec.ts / DomainHeader.spec.ts).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (k: string) => k }),
}));

// DeliveryPanel imports LanguageSelector, which transitively loads the language
// store + a real createI18n at module-eval time — incompatible with the fully
// mocked vue-i18n above (no createI18n). Mock the component module so the chain
// never loads; the Language card's own heading still renders via t().
vi.mock('@/apps/workspace/components/dashboard/LanguageSelector.vue', () => ({
  default: { name: 'LanguageSelector', template: '<div data-stub="language-selector" />' },
}));

const previewI18n = { t: (k: string) => k } as any;

// Stub the heavy leaves so these stay unit tests: the color picker (pulls in
// vue-color), the recipient preview column (SecretPreview → BaseSecretDisplay),
// and icons. Fonts are native <select>s (not a component), so nothing to stub.
const leafStubs = {
  ColorPicker: true,
  OIcon: true,
  BrandPreviewColumn: true,
  // The logo control has its own focused spec (BrandLogoField.spec.ts); stub it
  // here so the Simple-panel / editor tests stay about color/corners/font wiring.
  BrandLogoField: true,
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
  const mountPanel = (settings: Partial<BrandSettings> = {}, faviconSource: string | null = null) =>
    mount(SimpleBrandPanel, {
      props: {
        modelValue: baseSettings(settings),
        logoImage: null,
        onLogoUpload: vi.fn(),
        onLogoRemove: vi.fn(),
        onRefreshFavicon: vi.fn().mockResolvedValue(undefined),
        faviconSource,
      },
      global: { stubs: leafStubs },
    });

  // The favicon refresh control is the only button whose label echoes this key
  // (corner buttons carry borderRadiusDisplayMap English labels).
  const findRefreshButton = (wrapper: ReturnType<typeof mountPanel>) =>
    wrapper.findAll('button').find((b) => b.text().includes('web.branding.refresh_favicon'));

  it('writes border_radius when a corner is picked (Square→none, Extra Rounded→xl)', async () => {
    const wrapper = mountPanel({ border_radius: 'md' });
    const cornerButtons = wrapper.get('[role="group"]').findAll('button');
    expect(cornerButtons).toHaveLength(3);

    await cornerButtons[0].trigger('click'); // Square
    expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).toMatchObject({
      border_radius: 'none',
    });

    // The rounded ceiling is `xl` — the `full` (pill, 9999px) preset was removed
    // because it renders as a giant oval on large content boxes.
    await cornerButtons[2].trigger('click'); // Extra Rounded
    expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).toMatchObject({
      border_radius: 'xl',
    });
  });

  it('marks the active corner from the current border_radius', () => {
    const wrapper = mountPanel({ border_radius: 'xl' });
    const cornerButtons = wrapper.get('[role="group"]').findAll('button');
    // Square / Rounded / Extra Rounded → none / md / xl
    expect(cornerButtons[0].attributes('aria-pressed')).toBe('false');
    expect(cornerButtons[2].attributes('aria-pressed')).toBe('true');
  });

  it('shows one inline Font Family select (no disclosure, no heading font)', () => {
    const wrapper = mountPanel();
    // No "More options" disclosure — the font control is always visible.
    expect(wrapper.find('button[aria-expanded]').exists()).toBe(false);
    // Exactly one select: body font. Heading font was removed.
    const selects = wrapper.findAll('select');
    expect(selects).toHaveLength(1);
    // Picker is trimmed to the four curated families (serif/sans/mono/system);
    // the style-classification fonts (slab/rounded/humanist/geometric) render
    // near-identically across viewers, so they no longer appear in the editor.
    const values = selects[0].findAll('option').map((o) => o.attributes('value'));
    expect(values).toEqual(['serif', 'sans', 'mono', 'system']);
  });

  it('keeps a domain’s previously-set hidden font visible as an option', () => {
    // A domain saved under a now-hidden value (e.g. humanist) must not have its
    // selection silently dropped: the current value is prepended to the picker.
    const wrapper = mountPanel({ font_family: 'humanist' } as Partial<BrandSettings>);
    const select = wrapper.find('select');
    const values = select.findAll('option').map((o) => o.attributes('value'));
    expect(values).toEqual(['humanist', 'serif', 'sans', 'mono', 'system']);
    expect((select.element as HTMLSelectElement).value).toBe('humanist');
  });

  // #3780 — manual "Refresh favicon from domain" control.
  it('renders the refresh-favicon button and fires onRefreshFavicon on click', async () => {
    const onRefreshFavicon = vi.fn().mockResolvedValue(undefined);
    const wrapper = mount(SimpleBrandPanel, {
      props: {
        modelValue: baseSettings(),
        logoImage: null,
        onLogoUpload: vi.fn(),
        onLogoRemove: vi.fn(),
        onRefreshFavicon,
        faviconSource: null,
      },
      global: { stubs: leafStubs },
    });

    const button = wrapper.findAll('button').find((b) =>
      b.text().includes('web.branding.refresh_favicon')
    );
    expect(button?.exists()).toBe(true);

    await button!.trigger('click');
    expect(onRefreshFavicon).toHaveBeenCalledTimes(1);
  });

  it('leaves the button enabled for an empty or auto-fetched icon', () => {
    expect(
      (findRefreshButton(mountPanel({}, null))!.element as HTMLButtonElement).disabled
    ).toBe(false);
    expect(
      (findRefreshButton(mountPanel({}, 'auto_fetch'))!.element as HTMLButtonElement).disabled
    ).toBe(false);
  });

  it('disables the button when the favicon was user-uploaded (a forced fetch cannot overwrite it)', () => {
    const button = findRefreshButton(mountPanel({}, 'user_upload'));
    expect((button!.element as HTMLButtonElement).disabled).toBe(true);
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
        onRefreshFavicon: vi.fn().mockResolvedValue(undefined),
        previewI18n,
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

describe('DeliveryPanel', () => {
  const mountDelivery = (i18nEnabled = true) =>
    mount(DeliveryPanel, {
      // LanguageSelector is module-mocked above (severs the i18n/store chain).
      props: { modelValue: baseSettings(), i18nEnabled, previewI18n },
    });

  it('writes reveal instructions to the shared brandSettings record', async () => {
    const wrapper = mountDelivery();
    const inputs = wrapper.findAll('input');
    expect(inputs.length).toBe(2); // before + after reveal

    await inputs[0].setValue('Scan the QR code');
    expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).toMatchObject({
      instructions_pre_reveal: 'Scan the QR code',
    });

    await inputs[1].setValue('Store it safely');
    expect(wrapper.emitted('update:modelValue')?.at(-1)?.[0]).toMatchObject({
      instructions_post_reveal: 'Store it safely',
    });
  });

  it('hides the whole Language card when i18n is disabled', () => {
    // Enabled: the language card (heading + selector) is present.
    expect(mountDelivery(true).text()).toContain('web.branding.delivery_language');
    // Disabled: the card is gone entirely, not just the control (an empty
    // card reads as broken).
    expect(mountDelivery(false).text()).not.toContain('web.branding.delivery_language');
  });
});
