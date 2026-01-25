// src/tests/components/identifier-navigation.spec.ts

/**
 * Component tests for the Opaque Identifier Pattern
 *
 * Validates that navigation components use extid (not id) for URL construction.
 * Part of IDOR prevention strategy.
 *
 * @see src/types/identifiers.ts
 * @see docs/IDENTIFIER-REVIEW-CHECKLIST.md
 */

import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent } from 'vue';
import { createRouter, createWebHistory, type Router } from 'vue-router';

import { toExtId, toObjId, type ExtId, type ObjId } from '@/types/identifiers';
import type { Organization } from '@/types/organization';

// Mock organization data with branded types
const mockOrganization: Organization = {
  id: toObjId('550e8400-e29b-41d4-a716-446655440000'),
  extid: toExtId('on8a7b9c'),
  display_name: 'Test Organization',
  description: 'Test description',
  is_default: false,
  created_at: new Date('2024-01-01'),
  updated_at: new Date('2024-01-01'),
};

const mockOrganizations: Organization[] = [
  mockOrganization,
  {
    id: toObjId('660f9500-f39c-52e5-b827-557766551111'),
    extid: toExtId('on9c8d7e'),
    display_name: 'Second Organization',
    description: null,
    is_default: true,
    created_at: new Date('2024-02-01'),
    updated_at: new Date('2024-02-01'),
  },
];

/**
 * Creates a test router with organization routes
 */
function createTestRouter(): Router {
  return createRouter({
    history: createWebHistory(),
    routes: [
      { path: '/', name: 'home', component: { template: '<div>Home</div>' } },
      {
        path: '/org/:extid',
        name: 'organization',
        component: { template: '<div>Org</div>' },
      },
      {
        path: '/org/:extid/settings',
        name: 'organization-settings',
        component: { template: '<div>Settings</div>' },
      },
    ],
  });
}

/**
 * Creates a minimal i18n instance for tests
 */
function createTestI18n() {
  return createI18n({
    legacy: false,
    locale: 'en',
    fallbackLocale: 'en',
    messages: {
      en: {
        web: {
          organizations: {
            title: 'Organizations',
            organizations: 'Organizations',
          },
        },
      },
    },
  });
}

/**
 * Test component that simulates navigation patterns
 */
const NavigationTestComponent = defineComponent({
  name: 'NavigationTestComponent',
  props: {
    organization: {
      type: Object as () => Organization,
      required: true,
    },
  },
  emits: ['navigate'],
  setup(props, { emit }) {
    const handleNavigate = () => {
      // CORRECT: Use extid for navigation
      emit('navigate', props.organization.extid);
    };

    return { handleNavigate };
  },
  template: `
    <div>
      <button data-testid="nav-button" @click="handleNavigate">
        Navigate to {{ organization.display_name }}
      </button>
    </div>
  `,
});

/**
 * Test component demonstrating router-link pattern
 */
const RouterLinkTestComponent = defineComponent({
  name: 'RouterLinkTestComponent',
  props: {
    organization: {
      type: Object as () => Organization,
      required: true,
    },
  },
  setup(props) {
    // CORRECT: Build URL with extid
    const orgUrl = computed(() => `/org/${props.organization.extid}`);
    return { orgUrl };
  },
  template: `
    <div>
      <router-link :to="orgUrl" data-testid="org-link">
        {{ organization.display_name }}
      </router-link>
    </div>
  `,
});

/**
 * Test component demonstrating programmatic navigation
 */
const ProgrammaticNavComponent = defineComponent({
  name: 'ProgrammaticNavComponent',
  props: {
    organization: {
      type: Object as () => Organization,
      required: true,
    },
  },
  setup(props) {
    // Access router via injection (will be provided in tests)
    const router = {
      push: vi.fn(),
    };

    const navigateToOrg = () => {
      // CORRECT: Use extid for router.push
      router.push(`/org/${props.organization.extid}`);
    };

    return { navigateToOrg, router };
  },
  template: `
    <button data-testid="push-button" @click="navigateToOrg">
      Go to Organization
    </button>
  `,
});

describe('Identifier Navigation Pattern', () => {
  let router: Router;
  let i18n: ReturnType<typeof createTestI18n>;

  beforeEach(() => {
    router = createTestRouter();
    i18n = createTestI18n();
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('Navigation Events', () => {
    it('emits extid (not id) when navigation is triggered', async () => {
      const wrapper = mount(NavigationTestComponent, {
        props: { organization: mockOrganization },
        global: {
          plugins: [router, i18n],
        },
      });

      await wrapper.find('[data-testid="nav-button"]').trigger('click');

      const emitted = wrapper.emitted('navigate');
      expect(emitted).toBeTruthy();
      expect(emitted?.[0]).toEqual([mockOrganization.extid]);
      // Verify it's the extid format, not the UUID format
      expect(emitted?.[0]?.[0]).toBe('on8a7b9c');
      expect(emitted?.[0]?.[0]).not.toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      );
    });

    it('does not emit internal id for navigation', async () => {
      const wrapper = mount(NavigationTestComponent, {
        props: { organization: mockOrganization },
        global: {
          plugins: [router, i18n],
        },
      });

      await wrapper.find('[data-testid="nav-button"]').trigger('click');

      const emitted = wrapper.emitted('navigate');
      // Should NOT be the internal UUID
      expect(emitted?.[0]?.[0]).not.toBe(mockOrganization.id);
    });
  });

  describe('Router Link Props', () => {
    it('builds :to prop with extid', async () => {
      const wrapper = mount(RouterLinkTestComponent, {
        props: { organization: mockOrganization },
        global: {
          plugins: [router, i18n],
        },
      });

      const link = wrapper.find('[data-testid="org-link"]');
      expect(link.exists()).toBe(true);

      // Access the computed orgUrl via component instance
      const vm = wrapper.vm as unknown as { orgUrl: string };
      expect(vm.orgUrl).toBe('/org/on8a7b9c');

      // Also verify the router-link component received the correct :to prop
      const routerLink = wrapper.findComponent({ name: 'RouterLink' });
      expect(routerLink.props('to')).toBe('/org/on8a7b9c');
    });

    it('does not include internal id in URL path', async () => {
      const wrapper = mount(RouterLinkTestComponent, {
        props: { organization: mockOrganization },
        global: {
          plugins: [router, i18n],
        },
      });

      // Check the computed URL value directly
      const vm = wrapper.vm as unknown as { orgUrl: string };
      const url = vm.orgUrl;

      // Should NOT contain the internal UUID
      expect(url).not.toContain('550e8400');
      expect(url).not.toContain(mockOrganization.id as string);
    });
  });

  describe('Programmatic Navigation', () => {
    it('uses extid in router.push calls', async () => {
      const wrapper = mount(ProgrammaticNavComponent, {
        props: { organization: mockOrganization },
        global: {
          plugins: [router, i18n],
        },
      });

      await wrapper.find('[data-testid="push-button"]').trigger('click');

      // Access the component's mock router
      const vm = wrapper.vm as unknown as { router: { push: ReturnType<typeof vi.fn> } };
      expect(vm.router.push).toHaveBeenCalledWith('/org/on8a7b9c');
    });

    it('does not use internal id in router.push calls', async () => {
      const wrapper = mount(ProgrammaticNavComponent, {
        props: { organization: mockOrganization },
        global: {
          plugins: [router, i18n],
        },
      });

      await wrapper.find('[data-testid="push-button"]').trigger('click');

      const vm = wrapper.vm as unknown as { router: { push: ReturnType<typeof vi.fn> } };
      const calls = vm.router.push.mock.calls;

      // Verify the call doesn't contain internal ID
      calls.forEach((call: string[]) => {
        expect(call[0]).not.toContain('550e8400');
      });
    });
  });

  describe('Vue :key Binding (Correct id Usage)', () => {
    /**
     * Test component that correctly uses id for :key binding
     */
    const ListComponent = defineComponent({
      name: 'ListComponent',
      props: {
        organizations: {
          type: Array as () => Organization[],
          required: true,
        },
      },
      template: `
        <ul>
          <li
            v-for="org in organizations"
            :key="org.id"
            :data-id="org.id"
            :data-extid="org.extid"
          >
            {{ org.display_name }}
          </li>
        </ul>
      `,
    });

    it('uses id (not extid) for Vue :key binding', () => {
      const wrapper = mount(ListComponent, {
        props: { organizations: mockOrganizations },
        global: {
          plugins: [i18n],
        },
      });

      const items = wrapper.findAll('li');
      expect(items).toHaveLength(2);

      // Verify the component uses internal id for :key
      // The data-id attribute reflects what's used in :key
      expect(items[0].attributes('data-id')).toBe(mockOrganizations[0].id);
      expect(items[1].attributes('data-id')).toBe(mockOrganizations[1].id);
    });

    it('distinguishes between id (for :key) and extid (for URLs)', () => {
      const wrapper = mount(ListComponent, {
        props: { organizations: mockOrganizations },
        global: {
          plugins: [i18n],
        },
      });

      const items = wrapper.findAll('li');

      // id should be UUID format (internal)
      expect(items[0].attributes('data-id')).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      );

      // extid should be prefixed format (external)
      expect(items[0].attributes('data-extid')).toMatch(/^on[a-z0-9]+$/i);
    });
  });

  describe('Type Safety at Boundaries', () => {
    it('correctly types organization with ObjId and ExtId', () => {
      // This test verifies the type definitions are correctly applied
      const org = mockOrganization;

      // At runtime, both are strings
      expect(typeof org.id).toBe('string');
      expect(typeof org.extid).toBe('string');

      // But they have different formats
      expect(org.id).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      );
      expect(org.extid).toMatch(/^on[a-z0-9]+$/i);
    });

    it('creates branded types using constructor functions', () => {
      const rawId = 'test-internal-id';
      const rawExtId = 'on123abc';

      const objId: ObjId = toObjId(rawId);
      const extId: ExtId = toExtId(rawExtId);

      // Runtime values are preserved
      expect(objId).toBe(rawId);
      expect(extId).toBe(rawExtId);

      // But TypeScript sees them as different types
      // (compile-time check, not runtime)
    });
  });

  describe('URL Path Construction', () => {
    /**
     * Test component that builds various URL paths
     */
    const UrlBuilderComponent = defineComponent({
      name: 'UrlBuilderComponent',
      props: {
        organization: {
          type: Object as () => Organization,
          required: true,
        },
      },
      setup(props) {
        const viewPath = computed(() => `/org/${props.organization.extid}`);
        const settingsPath = computed(() => `/org/${props.organization.extid}/settings`);
        const apiPath = computed(() => `/api/organizations/${props.organization.extid}`);

        return { viewPath, settingsPath, apiPath };
      },
      template: `
        <div>
          <a :href="viewPath" data-testid="view-link">View</a>
          <a :href="settingsPath" data-testid="settings-link">Settings</a>
          <span data-testid="api-path">{{ apiPath }}</span>
        </div>
      `,
    });

    it('builds view path with extid', () => {
      const wrapper = mount(UrlBuilderComponent, {
        props: { organization: mockOrganization },
        global: { plugins: [i18n] },
      });

      expect(wrapper.find('[data-testid="view-link"]').attributes('href')).toBe(
        '/org/on8a7b9c'
      );
    });

    it('builds settings path with extid', () => {
      const wrapper = mount(UrlBuilderComponent, {
        props: { organization: mockOrganization },
        global: { plugins: [i18n] },
      });

      expect(wrapper.find('[data-testid="settings-link"]').attributes('href')).toBe(
        '/org/on8a7b9c/settings'
      );
    });

    it('builds API path with extid', () => {
      const wrapper = mount(UrlBuilderComponent, {
        props: { organization: mockOrganization },
        global: { plugins: [i18n] },
      });

      expect(wrapper.find('[data-testid="api-path"]').text()).toBe(
        '/api/organizations/on8a7b9c'
      );
    });

    it('never includes internal id in any URL paths', () => {
      const wrapper = mount(UrlBuilderComponent, {
        props: { organization: mockOrganization },
        global: { plugins: [i18n] },
      });

      const internalId = mockOrganization.id as string;

      expect(wrapper.find('[data-testid="view-link"]').attributes('href')).not.toContain(
        internalId
      );
      expect(
        wrapper.find('[data-testid="settings-link"]').attributes('href')
      ).not.toContain(internalId);
      expect(wrapper.find('[data-testid="api-path"]').text()).not.toContain(internalId);
    });
  });
});

describe('OrganizationCard-like Navigation Pattern', () => {
  /**
   * Simplified version of OrganizationCard for testing navigation
   */
  const OrganizationCardTest = defineComponent({
    name: 'OrganizationCardTest',
    props: {
      organization: {
        type: Object as () => Organization,
        required: true,
      },
    },
    emits: ['click'],
    setup(props, { emit }) {
      const handleClick = () => {
        emit('click');
      };
      return { handleClick };
    },
    template: `
      <button
        type="button"
        @click="handleClick"
        :data-org-extid="organization.extid"
        data-testid="org-card"
      >
        {{ organization.display_name }}
      </button>
    `,
  });

  it('exposes extid in data attribute for navigation handlers', () => {
    const i18n = createTestI18n();

    const wrapper = mount(OrganizationCardTest, {
      props: { organization: mockOrganization },
      global: { plugins: [i18n] },
    });

    const card = wrapper.find('[data-testid="org-card"]');
    expect(card.attributes('data-org-extid')).toBe('on8a7b9c');
  });

  it('parent component can use extid for navigation on click', async () => {
    const i18n = createTestI18n();
    const router = createTestRouter();
    const pushSpy = vi.spyOn(router, 'push');

    // Parent component that handles navigation
    const ParentComponent = defineComponent({
      components: { OrganizationCardTest },
      setup() {
        const org = mockOrganization;
        const handleOrgClick = () => {
          // CORRECT: Use extid for navigation
          router.push(`/org/${org.extid}`);
        };
        return { org, handleOrgClick };
      },
      template: `
        <OrganizationCardTest
          :organization="org"
          @click="handleOrgClick"
        />
      `,
    });

    const wrapper = mount(ParentComponent, {
      global: { plugins: [router, i18n] },
    });

    await wrapper.find('[data-testid="org-card"]').trigger('click');

    expect(pushSpy).toHaveBeenCalledWith('/org/on8a7b9c');
    expect(pushSpy).not.toHaveBeenCalledWith(expect.stringContaining('550e8400'));
  });
});
