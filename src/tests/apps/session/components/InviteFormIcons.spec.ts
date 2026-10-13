// src/tests/apps/session/components/InviteFormIcons.spec.ts
//
// The invite sign-in/sign-up specs don't render these icons against real
// sprites, so a misspelled name (e.g. `solid-lock-closed` for the locked email
// field) shipped as a blank icon. Checks every static OIcon in both forms.

import { describe, it, expect } from 'vitest';
import inviteSignInSource from '@/apps/session/components/InviteSignInForm.vue?raw';
import inviteSignUpSource from '@/apps/session/components/InviteSignUpForm.vue?raw';
import { loadSpriteSymbolIds, staticOIconIds } from '@tests/support/spriteSymbols';

describe.each([
  ['InviteSignInForm', inviteSignInSource],
  ['InviteSignUpForm', inviteSignUpSource],
])('%s icons', (_component, source) => {
  it('references only existing sprite symbols', async () => {
    const ids = await loadSpriteSymbolIds();
    const referenced = staticOIconIds(source);

    expect(referenced.filter((id) => !ids.has(id))).toEqual([]);
    // Guards against the source scan silently matching nothing.
    expect(referenced.length).toBeGreaterThan(0);
  });
});
