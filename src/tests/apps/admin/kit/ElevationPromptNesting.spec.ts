// src/tests/apps/admin/kit/ElevationPromptNesting.spec.ts

import { AxiosError } from 'axios';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref, type Ref, type VNode } from 'vue';

/**
 * The step-up prompt over an open admin dialog, with the REAL headlessui.
 *
 * headlessui 1.7 counts a Dialog as nested only when it renders inside the
 * parent Dialog's component subtree. Mounted as a SIBLING (AdminLayout's
 * instance), the prompt was outside to an open drawer or confirm dialog:
 *
 *   - its outside-click listener closed the drawer on any click into the
 *     prompt, and called preventDefault() on that click, so the prompt's
 *     submit button never submitted;
 *   - its window keydown listener ran first, so Escape closed the drawer and
 *     left the prompt open;
 *   - it made #app inert, so the password-less forks (a plain div in #app)
 *     could not be clicked at all.
 *
 * The fix nests the prompt in the top-most open kit dialog
 * (useElevationPromptHost). These examples dispatch the real mousedown/click
 * and keydown sequences headlessui listens for; the in-place headlessui stubs
 * other admin specs use cannot show any of this.
 */

const mockApi = { get: vi.fn(), post: vi.fn(), delete: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

// headlessui's Dialog watches its panel with a ResizeObserver; jsdom has none.
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
globalThis.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver;

import AdminConfirmDialog from '@/apps/admin/components/kit/AdminConfirmDialog.vue';
import DetailDrawer from '@/apps/admin/components/kit/DetailDrawer.vue';
import ElevationPrompt from '@/apps/admin/components/ElevationPrompt.vue';
import {
  useAdminDestructiveMutation,
  type UseAdminDestructiveMutation,
} from '@/apps/admin/composables/useAdminDestructiveMutation';
import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import {
  __resetElevationPromptHosts,
  useLayoutElevationPromptHost,
} from '@/apps/admin/composables/useElevationPromptHost';
import { useAuthStore } from '@/shared/stores/authStore';
import { createTestI18n } from '@tests/setup';
import { captureConsole } from '@tests/utils/appLogs';

const i18n = createTestI18n();

function statusPayload(details: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: { elevated: false, expires_at: null, seconds_remaining: 0 },
    details: {
      enabled: true,
      window: 600,
      reauth_grace: 0,
      grace_available: false,
      password_available: true,
      factors: ['password'],
      ...details,
    },
  };
}

function grantPayload(factor = 'password') {
  return {
    shrimp: '',
    record: { elevated: true, expires_at: 1_700_000_600, seconds_remaining: 600 },
    details: { factor, window: 600 },
  };
}

/** Let headlessui's transitions, focus microtasks and portals settle. */
async function settle(): Promise<void> {
  for (let i = 0; i < 5; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 10));
    await flushPromises();
  }
}

/** `settle()` until `done`, bounded: a leave transition plus a cancel needs more than one pass. */
async function settleUntil(done: () => boolean, passes = 10): Promise<void> {
  for (let i = 0; i < passes; i += 1) {
    await settle();
    if (done()) return;
  }
}

/** The pointer sequence headlessui's outside-click hook records, then the click. */
function realClick(el: Element): MouseEvent {
  el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
  const click = new MouseEvent('click', { bubbles: true, cancelable: true });
  el.dispatchEvent(click);
  return click;
}

function pressEscape(): void {
  (document.activeElement ?? document.body).dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })
  );
}

const q = <T extends Element = HTMLElement>(selector: string): T | null =>
  document.querySelector<T>(selector);

function isInert(el: Element | null): boolean {
  for (let node = el; node; node = node.parentElement) {
    if ((node as HTMLElement).inert) return true;
  }
  return false;
}

interface Counts {
  drawerCloses: Ref<number>;
  confirmCancels: Ref<number>;
}

/**
 * AdminLayout's arrangement: the page (a drawer with a confirm dialog in its
 * slot, as the views place it since #4732) plus the layout's own prompt
 * instance, mounted only while no kit dialog hosts it.
 */
function mountConsole(state: {
  drawer: Ref<boolean>;
  confirm: Ref<boolean>;
  /** Extra content for the drawer's body slot: a view that lives and dies with the drawer. */
  inDrawer?: () => VNode | null;
}): {
  wrapper: VueWrapper;
  counts: Counts;
} {
  const counts: Counts = { drawerCloses: ref(0), confirmCancels: ref(0) };
  const Harness = defineComponent({
    setup() {
      useColonelElevation();
      const layoutHostsPrompt = useLayoutElevationPromptHost();
      return () =>
        h('div', [
          h(
            DetailDrawer,
            {
              open: state.drawer.value,
              title: 'alice@example.com',
              testid: 'drawer',
              'onUpdate:open': (value: boolean) => (state.drawer.value = value),
              onClose: () => (counts.drawerCloses.value += 1),
            },
            {
              default: () => [
                h('button', { type: 'button', 'data-testid': 'drawer-action' }, 'Purge'),
                h(AdminConfirmDialog, {
                  open: state.confirm.value,
                  title: 'Purge',
                  'onUpdate:open': (value: boolean) => (state.confirm.value = value),
                  onCancel: () => (counts.confirmCancels.value += 1),
                }),
                state.inDrawer?.() ?? null,
              ],
            }
          ),
          layoutHostsPrompt.value ? h(ElevationPrompt) : null,
        ]);
    },
  });
  const wrapper = mount(Harness, { attachTo: document.body, global: { plugins: [i18n] } });
  return { wrapper, counts };
}

describe('the step-up prompt over an open admin dialog (real headlessui)', () => {
  let wrapper: VueWrapper | undefined;

  beforeEach(() => {
    vi.clearAllMocks();
    __resetColonelElevationState({ statusRead: true });
    __resetElevationPromptHosts();
    mockApi.get.mockResolvedValue({ data: statusPayload() });
    mockApi.post.mockResolvedValue({ data: grantPayload() });
    // A granted window adopts the renewed session id; not under test here.
    vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = undefined;
    __resetColonelElevationState();
    __resetElevationPromptHosts();
    document.body.replaceChildren();
  });

  describe('over a drawer', () => {
    it('renders ONE prompt, and clicks into it neither close the drawer nor swallow Confirm', async () => {
      const drawer = ref(true);
      const mounted = mountConsole({ drawer, confirm: ref(false) });
      wrapper = mounted.wrapper;
      await settle();

      const pending = useColonelElevation().requestElevation();
      await settle();

      expect(document.querySelectorAll('#password-confirm-input')).toHaveLength(1);
      const input = q<HTMLInputElement>('#password-confirm-input')!;

      const inputClick = realClick(input);
      await settle();
      expect(inputClick.defaultPrevented).toBe(false);
      expect(mounted.counts.drawerCloses.value).toBe(0);

      input.value = 'hunter2';
      input.dispatchEvent(new Event('input'));
      await settle();

      const submit = input.form!.querySelector<HTMLButtonElement>('button[type="submit"]')!;
      const submitClick = realClick(submit);
      await settle();

      // The FIRST click submits: nothing called preventDefault() on it.
      expect(submitClick.defaultPrevented).toBe(false);
      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/elevation', {
        factor: 'password',
        password: 'hunter2',
      });
      await expect(pending).resolves.toBe(true);

      // The drawer the operator is acting in is still open.
      expect(mounted.counts.drawerCloses.value).toBe(0);
      expect(drawer.value).toBe(true);
      expect(q('[data-testid="drawer"]')).not.toBeNull();
    });

    it('Escape cancels the prompt and leaves the drawer open', async () => {
      const drawer = ref(true);
      const mounted = mountConsole({ drawer, confirm: ref(false) });
      wrapper = mounted.wrapper;
      await settle();

      const pending = useColonelElevation().requestElevation();
      await settle();
      expect(document.activeElement?.id).toBe('password-confirm-input');

      pressEscape();
      await settle();

      await expect(pending).resolves.toBe(false);
      expect(useColonelElevation().promptOpen.value).toBe(false);
      expect(mounted.counts.drawerCloses.value).toBe(0);
      expect(drawer.value).toBe(true);
    });

    it('makes the drawer inert under the prompt, and live again after it', async () => {
      const drawer = ref(true);
      wrapper = mountConsole({ drawer, confirm: ref(false) }).wrapper;
      await settle();

      void useColonelElevation().requestElevation();
      await settle();
      expect(isInert(q('[data-testid="drawer-action"]'))).toBe(true);
      expect(isInert(q('#password-confirm-input'))).toBe(false);

      useColonelElevation().resolvePrompt(false);
      await settle();
      expect(isInert(q('[data-testid="drawer-action"]'))).toBe(false);
    });

    it('opens the confirm dialog inside the still-open drawer after elevating', async () => {
      const drawer = ref(true);
      const confirm = ref(false);
      const mounted = mountConsole({ drawer, confirm });
      wrapper = mounted.wrapper;
      await settle();

      // A tier-1 opener: elevate, then open the dialog.
      const elevation = useColonelElevation();
      const opened = elevation.requestElevation().then((ok) => {
        if (ok) confirm.value = true;
      });
      await settle();
      const input = q<HTMLInputElement>('#password-confirm-input')!;
      input.value = 'hunter2';
      input.dispatchEvent(new Event('input'));
      await settle();
      realClick(input.form!.querySelector('button[type="submit"]')!);
      await opened;
      await settle();

      expect(drawer.value).toBe(true);
      expect(q('[data-testid="admin-confirm-dialog"]')).not.toBeNull();
      expect(isInert(q('[data-testid="admin-confirm-cancel"]'))).toBe(false);
      expect(mounted.counts.drawerCloses.value).toBe(0);
    });
  });

  describe('over a confirm dialog (the 403 fallback)', () => {
    it('neither click nor Escape in the prompt cancels the confirm dialog under it', async () => {
      const confirm = ref(true);
      const mounted = mountConsole({ drawer: ref(true), confirm });
      wrapper = mounted.wrapper;
      await settle();

      const first = useColonelElevation().requestElevation();
      await settle();
      expect(document.querySelectorAll('#password-confirm-input')).toHaveLength(1);
      realClick(q('#password-confirm-input')!);
      await settle();
      expect(mounted.counts.confirmCancels.value).toBe(0);
      expect(confirm.value).toBe(true);

      pressEscape();
      await settle();
      await expect(first).resolves.toBe(false);
      expect(mounted.counts.confirmCancels.value).toBe(0);
      expect(confirm.value).toBe(true);
      expect(mounted.counts.drawerCloses.value).toBe(0);
    });
  });

  // Forks 2 and 3 used to be a plain div inside #app, which the open drawer
  // had made inert: the operator could not click Confirm or Close.
  describe('password-less forks', () => {
    it('renders the grace fork portaled and live, and its one click elevates', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({
          password_available: false,
          factors: ['recent_auth'],
          grace_available: true,
          reauth_grace: 300,
        }),
      });
      mockApi.post.mockResolvedValue({ data: grantPayload('recent_auth') });
      const drawer = ref(true);
      const mounted = mountConsole({ drawer, confirm: ref(false) });
      wrapper = mounted.wrapper;
      await settle();

      const pending = useColonelElevation().requestElevation();
      await settle();

      const panel = q('[data-testid="elevation-prompt-alt"]');
      expect(panel).not.toBeNull();
      expect(panel!.closest('#headlessui-portal-root')).not.toBeNull();
      const confirmItsYou = q('[data-testid="elevation-confirm-its-you"]')!;
      expect(isInert(confirmItsYou)).toBe(false);

      realClick(confirmItsYou);
      await settle();

      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/elevation', {
        factor: 'recent_auth',
        password: '',
      });
      await expect(pending).resolves.toBe(true);
      expect(mounted.counts.drawerCloses.value).toBe(0);
      expect(drawer.value).toBe(true);
    });

    it('renders the remediation fork portaled and live, and Close cancels only the prompt', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({ password_available: false, factors: [] }),
      });
      const drawer = ref(true);
      const mounted = mountConsole({ drawer, confirm: ref(false) });
      wrapper = mounted.wrapper;
      await settle();

      const pending = useColonelElevation().requestElevation();
      await settle();

      const remediation = q('[data-testid="elevation-prompt-unsatisfiable"]');
      expect(remediation).not.toBeNull();
      expect(remediation!.closest('#headlessui-portal-root')).not.toBeNull();
      const close = Array.from(
        q('[data-testid="elevation-prompt-alt"]')!.querySelectorAll('button')
      ).find((b) => b.textContent?.trim() === 'web.LABELS.close' && !b.getAttribute('aria-label'))!;
      expect(isInert(close)).toBe(false);

      realClick(close);
      await settle();

      await expect(pending).resolves.toBe(false);
      expect(mounted.counts.drawerCloses.value).toBe(0);
      expect(drawer.value).toBe(true);
    });
  });

  // The host invariant: the host stack must not change while the prompt is
  // open. A view inside the drawer that owns the 403 fallback prompt cancels
  // its request when the drawer closes (its scope is disposed with the slot),
  // so nothing is left for the layout's instance to show.
  describe('the drawer closes under the 403 fallback prompt', () => {
    function axiosError(status: number, data: unknown) {
      const err = new AxiosError('Request failed');
      err.response = { status, data, statusText: '', headers: {}, config: {} as never };
      return err;
    }

    /** A view in the drawer body that runs a tier-1 verb through the shared loop. */
    function callerInDrawer(perform: () => Promise<unknown>): {
      render: () => VNode;
      mutation: () => UseAdminDestructiveMutation<[]>;
    } {
      let mutation: UseAdminDestructiveMutation<[]> | undefined;
      const Caller = defineComponent({
        setup() {
          mutation = useAdminDestructiveMutation(perform);
          return () => h('span', { 'data-testid': 'drawer-caller' });
        },
      });
      return { render: () => h(Caller), mutation: () => mutation! };
    }

    it('leaves no prompt in the document, resolves run() false and never retries', async () => {
      const perform = vi
        .fn<() => Promise<unknown>>()
        .mockRejectedValueOnce(
          axiosError(403, { error: 'Step-up required', error_code: 'elevation_required' })
        )
        .mockResolvedValueOnce(undefined);
      const drawer = ref(true);
      const caller = callerInDrawer(perform);
      wrapper = mountConsole({ drawer, confirm: ref(false), inDrawer: caller.render }).wrapper;
      await settle();
      expect(q('[data-testid="drawer-caller"]')).not.toBeNull();

      const running = caller.mutation().run();
      await settle();
      expect(useColonelElevation().promptOpen.value).toBe(true);
      expect(document.querySelectorAll('#password-confirm-input')).toHaveLength(1);
      expect(perform).toHaveBeenCalledTimes(1);

      // Closing the top host under the open prompt cancels the prompt before
      // the token is released, so the layout never re-hosts it (next test).
      captureConsole('warn');
      drawer.value = false;
      await settleUntil(() => document.querySelectorAll('#password-confirm-input').length === 0);

      expect(q('[data-testid="drawer-caller"]')).toBeNull();
      expect(document.querySelectorAll('#password-confirm-input')).toHaveLength(0);
      expect(useColonelElevation().promptOpen.value).toBe(false);
      await expect(running).resolves.toBe(false);
      expect(perform).toHaveBeenCalledTimes(1);
    });

    // Ordering that this pins: the drawer's host token is released the moment
    // `open` flips (the prop watcher runs pre-flush), but its slot content
    // lives on through the headlessui leave transition, so the slot caller's
    // onScopeDispose would cancel the request only ~200 ms later. Without the
    // cancel-before-release rule in useElevationPromptHost the layout would
    // mount a second ElevationPrompt in between (typed password lost, focus
    // moved) and the dev guard would fire. The guard staying silent is the
    // assertion that the host stack did not change under the open prompt.
    it('does not move the prompt to the layout while the drawer is leaving', async () => {
      const perform = vi
        .fn<() => Promise<unknown>>()
        .mockRejectedValueOnce(
          axiosError(403, { error: 'Step-up required', error_code: 'elevation_required' })
        );
      const drawer = ref(true);
      const caller = callerInDrawer(perform);
      wrapper = mountConsole({ drawer, confirm: ref(false), inDrawer: caller.render }).wrapper;
      await settle();

      const running = caller.mutation().run();
      await settle();
      expect(useColonelElevation().promptOpen.value).toBe(true);

      const warn = captureConsole('warn');
      drawer.value = false;
      await settleUntil(() => useColonelElevation().promptOpen.value === false);
      await expect(running).resolves.toBe(false);

      expect(warn).not.toHaveBeenCalled();
    });

    // Positive control for the dev-only guard: a host that opens UNDER the
    // open prompt moves the prompt, and the watcher says so.
    it('the host-transition guard warns when a kit dialog opens under the open prompt', async () => {
      const confirm = ref(false);
      wrapper = mountConsole({ drawer: ref(true), confirm }).wrapper;
      await settle();

      const pending = useColonelElevation().requestElevation();
      await settle();
      const warn = captureConsole('warn');

      confirm.value = true;
      await settle();

      expect(warn).toHaveBeenCalledWith(expect.stringContaining('[useElevationPromptHost]'));
      useColonelElevation().resolvePrompt(false);
      await expect(pending).resolves.toBe(false);
    });
  });

  it('the layout hosts the prompt again once no kit dialog is open', async () => {
    wrapper = mountConsole({ drawer: ref(false), confirm: ref(false) }).wrapper;
    await settle();

    const pending = useColonelElevation().requestElevation();
    await settle();
    expect(document.querySelectorAll('#password-confirm-input')).toHaveLength(1);

    pressEscape();
    await settle();
    await expect(pending).resolves.toBe(false);
  });
});
