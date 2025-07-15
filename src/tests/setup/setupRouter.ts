// src/tests/setup/setupRouter.ts

/**
 * By default:
 *  - both <router-link> and <router-view> are stubbed
 *  - all navigation guards are ignored
 *
 * Vue Router Mock automatically detects if you are using Sinon.js,
 * Jest, or Vitest and use their spying methods.
 *
 * You can access the instance of the router mock in multiple ways:
 *   Access wrapper.router:
 *
 *      it('tests something', async () => {
 *        const wrapper = mount(MyComponent)
 *        await wrapper.router.push('/new-location')
 *      })
 *
 *   Access it through wrapper.vm:
 *
 *      it('tests something', async () => {
 *        const wrapper = mount(MyComponent)
 *        await wrapper.vm.$router.push('/new-location')
 *        expect(wrapper.vm.$route.name).toBe('NewLocation')
 *      })
 *
 *   Call getRouter() inside of a test:
 *
 *      it('tests something', async () => {
 *        // can be called before creating the wrapper
 *        const router = getRouter()
 *        const wrapper = mount(MyComponent)
 *        await router.push('/new-location')
 *      })
 *
 * @see https://www.npmjs.com/package/vue-router-mock#caveats
 */

import { VueRouterMock, createRouterMock, injectRouterMock } from 'vue-router-mock';
import { config } from '@vue/test-utils';
import { beforeEach } from 'vitest';

// create one router per test file
const router = createRouterMock();

beforeEach(() => {
  router.reset(); // reset the router state
  injectRouterMock(router);
});

// Add properties to the wrapper
config.plugins.VueWrapper.install(VueRouterMock);
