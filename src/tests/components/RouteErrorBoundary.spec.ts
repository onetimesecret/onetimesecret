// src/tests/components/RouteErrorBoundary.spec.ts
//
// Verifies the render error boundary converts a thrown child subtree into a
// visible fallback panel (never a blank page) and recovers when the route
// (resetKey) changes to a healthy component.

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { defineComponent, h, ref, nextTick, type Component } from 'vue';
import {
  createRouter,
  createMemoryHistory,
  RouterView,
  useRoute,
} from 'vue-router';
import RouteErrorBoundary from '@/shared/components/errors/RouteErrorBoundary.vue';

// Mirror production: the app installs `app.config.errorHandler`
// (src/plugins/core/globalErrorBoundary.ts) which absorbs the error the
// boundary re-propagates for Sentry. Without it, Vue re-throws and the test
// runner reports the (expected) error as a failure.
const withGlobalHandler = { global: { config: { errorHandler: () => {} } } };

// A child that throws synchronously during setup() — the exact shape that
// leaves <router-view> blank without a boundary.
const Exploding = defineComponent({
  name: 'Exploding',
  setup() {
    throw new Error('kaboom');
  },
  render: () => h('div', 'never rendered'),
});

const Healthy = defineComponent({
  name: 'Healthy',
  render: () => h('div', { 'data-testid': 'healthy' }, 'all good'),
});

describe('RouteErrorBoundary', () => {
  it('renders the fallback panel instead of a blank page when a child throws', async () => {
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    const wrapper = mount(RouteErrorBoundary, {
      ...withGlobalHandler,
      props: { resetKey: '/dashboard' },
      slots: { default: () => h(Exploding) },
    });
    await flushPromises();

    expect(wrapper.find('[data-testid="route-error-boundary"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="route-error-reload"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('never rendered');

    errSpy.mockRestore();
  });

  it('renders children normally when nothing throws', () => {
    const wrapper = mount(RouteErrorBoundary, {
      props: { resetKey: '/dashboard' },
      slots: { default: () => h(Healthy) },
    });

    expect(wrapper.find('[data-testid="healthy"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="route-error-boundary"]').exists()).toBe(false);
  });

  it('recovers on navigation: clears the error and renders the next healthy route', async () => {
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    // Harness mimics <router-view>: resetKey + the active component change
    // together on navigation.
    const routeKey = ref('/broken');
    const broken = ref(true);
    const Harness = defineComponent({
      render: () =>
        h(
          RouteErrorBoundary,
          { resetKey: routeKey.value },
          {
            default: () => (broken.value ? h(Exploding) : h(Healthy)),
          }
        ),
    });

    const wrapper = mount(Harness, withGlobalHandler);
    await flushPromises();
    expect(wrapper.find('[data-testid="route-error-boundary"]').exists()).toBe(true);

    // Navigate to a healthy route.
    broken.value = false;
    routeKey.value = '/dashboard';
    await nextTick();
    await flushPromises();

    expect(wrapper.find('[data-testid="route-error-boundary"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="healthy"]').exists()).toBe(true);

    errSpy.mockRestore();
  });

  // Real-router integration mirroring App.vue's exact wiring:
  //   <router-view v-slot="{ Component }">
  //     <RouteErrorBoundary :reset-key="$route.fullPath">
  //       <component :is="Component" :key="$route.fullPath" />
  //     </RouteErrorBoundary>
  //   </router-view>
  // The hand-rolled Harness above swaps the slot with a fresh unkeyed vnode and
  // awaits several ticks, so it can't catch a render-ordering regression in the
  // reset. This drives an actual vue-router navigation (broken -> healthy) so a
  // stuck boundary would surface here. Guards the T-Rex-reported recovery bug.
  it('recovers through a real router-view when navigating off a broken route', async () => {
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/broken', component: Exploding },
        { path: '/healthy', component: Healthy },
      ],
    });

    // Faithful copy of App.vue's router-view slot: unkeyed boundary persists
    // across navigation; the child is keyed and reset by $route.fullPath.
    const AppLikeHarness = defineComponent({
      setup() {
        const route = useRoute();
        return () =>
          h(RouterView, null, {
            default: ({ Component }: { Component: Component | undefined }) =>
              h(
                RouteErrorBoundary,
                { resetKey: route.fullPath },
                { default: () => (Component ? h(Component, { key: route.fullPath }) : null) }
              ),
          });
      },
    });

    router.push('/broken');
    await router.isReady();

    const wrapper = mount(AppLikeHarness, {
      global: {
        plugins: [router],
        // Render the real RouterView; @vue/test-utils auto-stubs it otherwise,
        // which would collapse the slot and make this a hollow test.
        stubs: { RouterView: false },
        config: { errorHandler: () => {} },
      },
    });
    await flushPromises();

    // Broken route -> fallback panel, no blank page.
    expect(wrapper.find('[data-testid="route-error-boundary"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="healthy"]').exists()).toBe(false);

    // Navigate to the healthy route -> the boundary must clear and render it.
    await router.push('/healthy');
    await flushPromises();

    expect(wrapper.find('[data-testid="route-error-boundary"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="healthy"]').exists()).toBe(true);

    errSpy.mockRestore();
  });
});
