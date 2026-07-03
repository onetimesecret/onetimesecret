// src/tests/components/RouteErrorBoundary.spec.ts
//
// Verifies the render error boundary converts a thrown child subtree into a
// visible fallback panel (never a blank page) and recovers when the route
// (resetKey) changes to a healthy component.

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { defineComponent, h, ref, nextTick } from 'vue';
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
});
