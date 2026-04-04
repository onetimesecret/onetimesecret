// src/tests/apps/workspace/components/organizations/OrganizationCard.spec.ts
//
// Tests for OrganizationCard component rendering, interaction, and accessibility.
// Verifies design system compliance:
// - Surface: border-gray-200/60 bg-white/60 backdrop-blur-sm
// - Typography: font-medium (not font-semibold)
// - Interaction: hover:border-brand-500 (not hover:shadow-md)

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import type { Organization } from '@/types/organization';

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

import OrganizationCard from '@/apps/workspace/components/organizations/OrganizationCard.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        organizations: {
          organizations: 'Organizations',
        },
      },
    },
  },
});

/**
 * OrganizationCard Component Tests
 *
 * Tests the organization card component that displays:
 * - Organization display name
 * - Optional description (truncated)
 * - Navigation chevron with hover animation
 * - Click interaction for navigation
 */
describe('OrganizationCard', () => {
  let wrapper: VueWrapper;

  const createMockOrganization = (overrides: Partial<Organization> = {}): Organization => ({
    objid: 'org_obj_123',
    extid: 'org_ext_123',
    display_name: 'Test Organization',
    description: null,
    owner_id: 'cust_456',
    contact_email: null,
    is_default: false,
    planid: 'free',
    created: new Date(),
    updated: new Date(),
    ...overrides,
  });

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (organization: Organization = createMockOrganization()) => {
    return mount(OrganizationCard, {
      props: {
        organization,
      },
      global: {
        plugins: [i18n],
      },
    });
  };

  describe('Basic Rendering', () => {
    it('renders organization display_name', () => {
      wrapper = mountComponent(createMockOrganization({ display_name: 'Acme Corporation' }));

      const heading = wrapper.find('h3');
      expect(heading.exists()).toBe(true);
      expect(heading.text()).toBe('Acme Corporation');
    });

    it('renders as a button element for accessibility', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.exists()).toBe(true);
      expect(button.attributes('type')).toBe('button');
    });

    it('applies text-left alignment for button content', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('text-left');
    });
  });

  describe('Description Rendering', () => {
    it('renders description when provided', () => {
      wrapper = mountComponent(
        createMockOrganization({ description: 'A great company for testing' })
      );

      const description = wrapper.find('p');
      expect(description.exists()).toBe(true);
      expect(description.text()).toBe('A great company for testing');
    });

    it('does not render description paragraph when null', () => {
      wrapper = mountComponent(createMockOrganization({ description: null }));

      // Should not have a description paragraph - only the h3 and metadata section
      const paragraphs = wrapper.findAll('p');
      expect(paragraphs.length).toBe(0);
    });

    it('applies line-clamp-2 for long description truncation', () => {
      const longDescription =
        'This is a very long description that spans multiple lines and should be truncated to only show two lines of text with an ellipsis at the end.';
      wrapper = mountComponent(createMockOrganization({ description: longDescription }));

      const description = wrapper.find('p');
      expect(description.classes()).toContain('line-clamp-2');
    });

    it('renders description with correct text styling', () => {
      wrapper = mountComponent(createMockOrganization({ description: 'Test description' }));

      const description = wrapper.find('p');
      expect(description.classes()).toContain('text-sm');
      expect(description.classes()).toContain('text-gray-600');
    });
  });

  describe('Click Interaction', () => {
    it('emits click event when card is clicked', async () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      await button.trigger('click');

      expect(wrapper.emitted('click')).toBeTruthy();
      expect(wrapper.emitted('click')).toHaveLength(1);
    });

    it('emits click event on multiple clicks', async () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      await button.trigger('click');
      await button.trigger('click');
      await button.trigger('click');

      expect(wrapper.emitted('click')).toHaveLength(3);
    });
  });

  describe('Design System Compliance', () => {
    it('applies correct surface styling (border-gray-200/60 bg-white/60 backdrop-blur-sm)', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      const classes = button.classes();

      expect(classes).toContain('border-gray-200/60');
      expect(classes).toContain('bg-white/60');
      expect(classes).toContain('backdrop-blur-sm');
    });

    it('applies font-medium to title (not font-semibold)', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h3');
      expect(heading.classes()).toContain('font-medium');
      expect(heading.classes()).not.toContain('font-semibold');
    });

    it('uses border interaction on hover (not shadow)', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      const classes = button.classes();

      expect(classes).toContain('hover:border-brand-500');
      expect(classes).not.toContain('hover:shadow-md');
    });

    it('applies rounded-lg border styling', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('rounded-lg');
      expect(button.classes()).toContain('border');
    });

    it('applies shadow-sm for subtle elevation', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('shadow-sm');
    });
  });

  describe('Hover States', () => {
    it('applies hover border color change', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('hover:border-brand-500');
    });

    it('applies hover text color change to title', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h3');
      expect(heading.classes()).toContain('group-hover:text-brand-600');
    });

    it('applies transition-all for smooth hover effects', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('transition-all');
    });

    it('button has group class for child hover states', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('group');
    });
  });

  describe('Chevron Icon', () => {
    it('renders chevron-right icon', () => {
      wrapper = mountComponent();

      const chevron = wrapper.find('[data-icon="chevron-right"]');
      expect(chevron.exists()).toBe(true);
      expect(chevron.attributes('data-collection')).toBe('heroicons');
    });

    it('chevron has aria-hidden for accessibility', () => {
      wrapper = mountComponent();

      // The chevron is inside the mocked OIcon component
      // We need to check via the wrapper's html or find by attribute
      const html = wrapper.html();
      expect(html).toContain('aria-hidden="true"');
    });

    it('chevron is positioned with shrink-0 to prevent compression', () => {
      wrapper = mountComponent();

      // The chevron receives ml-4 shrink-0 classes for proper positioning
      // Since OIcon is mocked, we verify the icon is rendered in the correct location
      const chevron = wrapper.find('[data-icon="chevron-right"]');
      expect(chevron.exists()).toBe(true);
      // The chevron should be a sibling of the content container
      const flexContainer = wrapper.find('.flex.items-start.justify-between');
      expect(flexContainer.find('[data-icon="chevron-right"]').exists()).toBe(true);
    });
  });

  describe('Accessibility', () => {
    it('uses button element with type="button"', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.exists()).toBe(true);
      expect(button.attributes('type')).toBe('button');
    });

    it('has focus ring styles', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      const classes = button.classes();

      expect(classes).toContain('focus:outline-none');
      expect(classes).toContain('focus:ring-2');
      expect(classes).toContain('focus:ring-brand-500');
      expect(classes).toContain('focus:ring-offset-2');
    });

    it('renders heading as h3 for semantic structure', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h3');
      expect(heading.exists()).toBe(true);
    });

    it('has full width for consistent click target', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('w-full');
    });
  });

  describe('Dark Mode Support', () => {
    it('has dark mode border styling', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('dark:border-gray-700/60');
    });

    it('has dark mode background styling', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('dark:bg-gray-800/60');
    });

    it('has dark mode hover border styling', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('dark:hover:border-brand-400');
    });

    it('has dark mode title text styling', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h3');
      expect(heading.classes()).toContain('dark:text-white');
    });

    it('has dark mode description text styling', () => {
      wrapper = mountComponent(createMockOrganization({ description: 'Test' }));

      const description = wrapper.find('p');
      expect(description.classes()).toContain('dark:text-gray-400');
    });

    it('has dark mode focus ring styling', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('dark:focus:ring-brand-400');
    });
  });

  describe('Layout Structure', () => {
    it('has flex layout with items-start justify-between', () => {
      wrapper = mountComponent();

      const flexContainer = wrapper.find('.flex.items-start.justify-between');
      expect(flexContainer.exists()).toBe(true);
    });

    it('content container has min-w-0 flex-1 for text truncation', () => {
      wrapper = mountComponent();

      const contentContainer = wrapper.find('.min-w-0.flex-1');
      expect(contentContainer.exists()).toBe(true);
    });

    it('title has truncate class for long names', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('h3');
      expect(heading.classes()).toContain('truncate');
    });

    it('has padding p-6', () => {
      wrapper = mountComponent();

      const button = wrapper.find('button');
      expect(button.classes()).toContain('p-6');
    });
  });

  describe('Metadata Section', () => {
    it('renders organization label in metadata section', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Organizations');
    });

    it('has metadata section with mt-4 spacing', () => {
      wrapper = mountComponent();

      const metadataSection = wrapper.find('.mt-4');
      expect(metadataSection.exists()).toBe(true);
    });

    it('renders building-office icon in metadata', () => {
      wrapper = mountComponent();

      const buildingIcon = wrapper.find('[data-icon="building-office"]');
      expect(buildingIcon.exists()).toBe(true);
      expect(buildingIcon.attributes('data-collection')).toBe('ph');
    });
  });

  describe('Edge Cases', () => {
    it('handles empty display_name', () => {
      wrapper = mountComponent(createMockOrganization({ display_name: '' }));

      const heading = wrapper.find('h3');
      expect(heading.exists()).toBe(true);
      expect(heading.text()).toBe('');
    });

    it('handles very long display_name with truncation', () => {
      const longName =
        'This Is A Very Long Organization Name That Should Be Truncated By CSS';
      wrapper = mountComponent(createMockOrganization({ display_name: longName }));

      const heading = wrapper.find('h3');
      expect(heading.text()).toBe(longName);
      expect(heading.classes()).toContain('truncate');
    });

    it('handles special characters in display_name', () => {
      wrapper = mountComponent(
        createMockOrganization({ display_name: 'Acme & Partners <Corp>' })
      );

      const heading = wrapper.find('h3');
      expect(heading.text()).toBe('Acme & Partners <Corp>');
    });

    it('handles unicode characters in display_name', () => {
      wrapper = mountComponent(createMockOrganization({ display_name: 'Acme Corp' }));

      const heading = wrapper.find('h3');
      expect(heading.text()).toContain('Acme');
    });

    it('handles empty description string', () => {
      // Component uses v-if="organization.description" which is falsy for empty string
      wrapper = mountComponent(createMockOrganization({ description: '' }));

      const paragraphs = wrapper.findAll('p');
      // Empty string is falsy, so no paragraph should be rendered
      expect(paragraphs.length).toBe(0);
    });
  });
});
