// src/tests/sources/ssoProviderIcons.spec.ts
//
// OIcon renders <use href="#<collection>-<name>">; a name with no matching
// <symbol> draws nothing and fails silently. SsoButton.spec.ts mocks OIcon, so
// these specs check every SSO icon against the sprites App.vue actually loads.

import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import OIcon from '@/shared/components/icons/OIcon.vue';
import {
  SSO_FALLBACK_ICON,
  SSO_PROVIDER_ICONS,
  ssoProviderIcon,
} from '@/sources/ssoProviderIcons';
import { loadSpriteSymbolIds } from '@tests/support/spriteSymbols';

describe('ssoProviderIcons', () => {
  it('maps every provider icon to an existing sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();
    const missing = Object.entries(SSO_PROVIDER_ICONS)
      .map(([route, icon]) => [route, `${icon.collection}-${icon.name}`])
      .filter(([, id]) => !ids.has(id));

    expect(missing).toEqual([]);
  });

  it('falls back to an existing sprite symbol', async () => {
    const ids = await loadSpriteSymbolIds();

    expect(ids.has(`${SSO_FALLBACK_ICON.collection}-${SSO_FALLBACK_ICON.name}`)).toBe(true);
  });

  it('uses the fallback for the generic oidc route', () => {
    expect(ssoProviderIcon('oidc')).toEqual(SSO_FALLBACK_ICON);
  });

  it('resolves through OIcon to the sprite id for the generic oidc route', async () => {
    const ids = await loadSpriteSymbolIds();
    const wrapper = mount(OIcon, { props: ssoProviderIcon('oidc') });
    const href = wrapper.find('use').attributes('href') ?? '';

    expect(ids.has(href.replace(/^#/, ''))).toBe(true);
  });
});
