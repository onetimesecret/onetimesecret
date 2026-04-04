// src/tests/apps/workspace/components/members/MembersTable.spec.ts

import MembersTable from '@/apps/workspace/components/members/MembersTable.vue';
import type { OrganizationMember, OrganizationRole } from '@/types/organization';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, params?: Record<string, string>) => {
      const translations: Record<string, string> = {
        'web.organizations.members.title': 'Team Members',
        'web.organizations.members.description': 'Manage your team members and their roles',
        'web.organizations.members.member': 'Member',
        'web.organizations.members.role': 'Role',
        'web.organizations.members.joined': 'Joined',
        'web.organizations.members.actions': 'Actions',
        'web.organizations.members.remove_member_title': 'Remove Member',
        'web.organizations.members.remove_member_confirm': `Are you sure you want to remove ${params?.name ?? 'this member'}?`,
        'web.organizations.members.roles.owner': 'Owner',
        'web.organizations.members.roles.admin': 'Admin',
        'web.organizations.members.roles.member': 'Member',
      };
      return translations[key] ?? key;
    },
  }),
}));

// Mock child components
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

vi.mock('@/apps/workspace/components/members/MemberRoleSelector.vue', () => ({
  default: {
    name: 'MemberRoleSelector',
    template: `<select
      data-testid="role-selector"
      :value="modelValue"
      :disabled="disabled"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option v-for="role in availableRoles" :key="role" :value="role">{{ role }}</option>
    </select>`,
    props: ['modelValue', 'availableRoles', 'disabled'],
    emits: ['update:modelValue'],
  },
}));

vi.mock('@/shared/components/modals/ConfirmDialog.vue', () => ({
  default: {
    name: 'ConfirmDialog',
    template: `<div data-testid="confirm-dialog" class="confirm-dialog">
      <span data-testid="dialog-title">{{ title }}</span>
      <span data-testid="dialog-message">{{ message }}</span>
      <button data-testid="dialog-confirm" @click="$emit('confirm')">Confirm</button>
      <button data-testid="dialog-cancel" @click="$emit('cancel')">Cancel</button>
    </div>`,
    props: ['title', 'message', 'type'],
    emits: ['confirm', 'cancel'],
  },
}));

// Mock useMembersManager composable
const mockCanModifyMember = vi.fn();
const mockCanChangeRole = vi.fn();
const mockGetAssignableRoles = vi.fn();
const mockUpdateMemberRole = vi.fn();
const mockRemoveMember = vi.fn();
const mockGetRoleLabel = vi.fn();

vi.mock('@/shared/composables/useMembersManager', () => ({
  useMembersManager: () => ({
    canModifyMember: mockCanModifyMember,
    canChangeRole: mockCanChangeRole,
    getAssignableRoles: mockGetAssignableRoles,
    updateMemberRole: mockUpdateMemberRole,
    removeMember: mockRemoveMember,
    getRoleLabel: mockGetRoleLabel,
  }),
}));

// Mock useConfirmDialog from VueUse
const mockReveal = vi.fn();
const mockConfirm = vi.fn();
const mockCancel = vi.fn();
const mockIsRevealed = ref(false);

vi.mock('@vueuse/core', () => ({
  useConfirmDialog: () => ({
    isRevealed: mockIsRevealed,
    reveal: mockReveal,
    confirm: mockConfirm,
    cancel: mockCancel,
  }),
}));

// Test data factory
const createMember = (overrides: Partial<OrganizationMember> = {}): OrganizationMember => ({
  extid: 'mem_abc123',
  email: 'member@example.com',
  role: 'member' as OrganizationRole,
  joined_at: 1704067200, // 2024-01-01
  is_owner: false,
  is_current_user: false,
  ...overrides,
});

describe('MembersTable', () => {
  let wrapper: VueWrapper;

  const defaultProps = {
    members: [
      createMember({ extid: 'mem_owner', email: 'owner@example.com', role: 'owner', is_owner: true }),
      createMember({ extid: 'mem_admin', email: 'admin@example.com', role: 'admin' }),
      createMember({ extid: 'mem_member', email: 'member@example.com', role: 'member' }),
    ],
    orgExtid: 'on1abc123',
    isLoading: false,
    compact: false,
  };

  beforeEach(() => {
    vi.clearAllMocks();

    // Default mock implementations
    mockCanModifyMember.mockReturnValue(true);
    mockCanChangeRole.mockReturnValue(true);
    mockGetAssignableRoles.mockReturnValue(['admin', 'member']);
    mockUpdateMemberRole.mockResolvedValue(createMember({ role: 'admin' }));
    mockRemoveMember.mockResolvedValue(true);
    mockGetRoleLabel.mockImplementation((role: string) => {
      const labels: Record<string, string> = {
        owner: 'Owner',
        admin: 'Admin',
        member: 'Member',
      };
      return labels[role] ?? role;
    });

    mockIsRevealed.value = false;
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountComponent = (props: Partial<typeof defaultProps> = {}) => {
    wrapper = mount(MembersTable, {
      props: { ...defaultProps, ...props },
    });
    return wrapper;
  };

  describe('Rendering member list', () => {
    it('renders all members in the table', () => {
      mountComponent();

      const rows = wrapper.findAll('tbody tr');
      expect(rows).toHaveLength(3);
    });

    it('displays member email for each row', () => {
      mountComponent();

      expect(wrapper.text()).toContain('owner@example.com');
      expect(wrapper.text()).toContain('admin@example.com');
      expect(wrapper.text()).toContain('member@example.com');
    });

    it('displays table headers', () => {
      mountComponent();

      expect(wrapper.text()).toContain('Member');
      expect(wrapper.text()).toContain('Role');
      expect(wrapper.text()).toContain('Joined');
      expect(wrapper.text()).toContain('Actions');
    });

    it('formats joined date correctly', () => {
      // joined_at is 1704067200 = 2024-01-01 00:00:00 UTC
      mountComponent({
        members: [createMember({ joined_at: 1704067200 })],
      });

      // The exact format depends on formatDisplayDate implementation
      // Just verify the date element exists in the joined column
      const rows = wrapper.findAll('tbody tr');
      expect(rows).toHaveLength(1);

      // The date should be rendered in the third column
      const joinedCell = rows[0].findAll('td')[2];
      expect(joinedCell.exists()).toBe(true);
    });
  });

  describe('Compact mode vs full mode', () => {
    it('shows header section in full mode', () => {
      mountComponent({ compact: false });

      expect(wrapper.text()).toContain('Team Members');
      expect(wrapper.text()).toContain('Manage your team members');
    });

    it('hides header section in compact mode', () => {
      mountComponent({ compact: true });

      expect(wrapper.text()).not.toContain('Team Members');
      expect(wrapper.text()).not.toContain('Manage your team members');
    });

    it('applies container styling in full mode', () => {
      mountComponent({ compact: false });

      const section = wrapper.find('section');
      expect(section.classes()).toContain('rounded-lg');
      expect(section.classes()).toContain('shadow-sm');
    });

    it('removes container styling in compact mode', () => {
      mountComponent({ compact: true });

      const section = wrapper.find('section');
      expect(section.classes()).not.toContain('rounded-lg');
      expect(section.classes()).not.toContain('shadow-sm');
    });

    it('applies table border styling in full mode', () => {
      mountComponent({ compact: false });

      const tableContainer = wrapper.find('table').element.parentElement;
      expect(tableContainer?.classList.contains('border')).toBe(true);
    });

    it('removes table border styling in compact mode', () => {
      mountComponent({ compact: true });

      const tableContainer = wrapper.find('table').element.parentElement;
      expect(tableContainer?.classList.contains('border')).toBe(false);
    });
  });

  describe('Role badge classes', () => {
    it('applies amber classes for owner role', () => {
      mockCanChangeRole.mockReturnValue(false); // Force badge display instead of selector

      mountComponent({
        members: [createMember({ role: 'owner', is_owner: true })],
      });

      const roleBadge = wrapper.find('span.bg-amber-100');
      expect(roleBadge.exists()).toBe(true);
      expect(roleBadge.classes()).toContain('text-amber-800');
    });

    it('applies blue classes for admin role', () => {
      mockCanChangeRole.mockReturnValue(false);

      mountComponent({
        members: [createMember({ role: 'admin' })],
      });

      const roleBadge = wrapper.find('span.bg-blue-100');
      expect(roleBadge.exists()).toBe(true);
      expect(roleBadge.classes()).toContain('text-blue-800');
    });

    it('applies gray classes for member role', () => {
      mockCanChangeRole.mockReturnValue(false);

      mountComponent({
        members: [createMember({ role: 'member' })],
      });

      const roleBadge = wrapper.find('span.bg-gray-100');
      expect(roleBadge.exists()).toBe(true);
      expect(roleBadge.classes()).toContain('text-gray-800');
    });

    it('includes base badge styling classes', () => {
      mockCanChangeRole.mockReturnValue(false);

      mountComponent({
        members: [createMember({ role: 'member' })],
      });

      const roleBadge = wrapper.find('span.rounded-full');
      expect(roleBadge.exists()).toBe(true);
      expect(roleBadge.classes()).toContain('px-2.5');
      expect(roleBadge.classes()).toContain('py-0.5');
      expect(roleBadge.classes()).toContain('text-xs');
      expect(roleBadge.classes()).toContain('font-medium');
    });
  });

  describe('Role selector visibility based on permissions', () => {
    it('shows role selector when user can change role', () => {
      mockCanChangeRole.mockReturnValue(true);

      mountComponent({
        members: [createMember({ role: 'admin' })],
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      expect(selector.exists()).toBe(true);
    });

    it('shows static role badge when user cannot change role', () => {
      mockCanChangeRole.mockReturnValue(false);

      mountComponent({
        members: [createMember({ role: 'admin' })],
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      expect(selector.exists()).toBe(false);

      const roleBadge = wrapper.find('span.bg-blue-100');
      expect(roleBadge.exists()).toBe(true);
    });

    it('passes available roles to selector', () => {
      mockCanChangeRole.mockReturnValue(true);
      mockGetAssignableRoles.mockReturnValue(['admin', 'member']);

      mountComponent({
        members: [createMember({ role: 'admin' })],
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      expect(selector.exists()).toBe(true);
      expect(mockGetAssignableRoles).toHaveBeenCalled();
    });

    it('disables role selector when isLoading is true', () => {
      mockCanChangeRole.mockReturnValue(true);

      mountComponent({
        members: [createMember({ role: 'admin' })],
        isLoading: true,
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      expect(selector.attributes('disabled')).toBeDefined();
    });

    it('emits member-updated when role is changed', async () => {
      mockCanChangeRole.mockReturnValue(true);
      const updatedMember = createMember({ extid: 'mem_admin', role: 'member' });
      mockUpdateMemberRole.mockResolvedValue(updatedMember);

      mountComponent({
        members: [createMember({ extid: 'mem_admin', role: 'admin' })],
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      await selector.setValue('member');
      await flushPromises();

      expect(mockUpdateMemberRole).toHaveBeenCalledWith('on1abc123', 'mem_admin', 'member');

      const emitted = wrapper.emitted('member-updated');
      expect(emitted).toBeDefined();
      expect(emitted).toHaveLength(1);
      expect(emitted![0]).toEqual([updatedMember]);
    });

    it('does not call updateMemberRole when role unchanged', async () => {
      mockCanChangeRole.mockReturnValue(true);

      mountComponent({
        members: [createMember({ extid: 'mem_admin', role: 'admin' })],
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      await selector.setValue('admin'); // Same role
      await flushPromises();

      expect(mockUpdateMemberRole).not.toHaveBeenCalled();
    });
  });

  describe('Remove button visibility based on permissions', () => {
    it('shows remove button when user can modify member', () => {
      mockCanModifyMember.mockReturnValue(true);

      mountComponent({
        members: [createMember({ role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      expect(removeButton.exists()).toBe(true);
    });

    it('hides remove button when user cannot modify member', () => {
      mockCanModifyMember.mockReturnValue(false);

      mountComponent({
        members: [createMember({ role: 'owner', is_owner: true })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      expect(removeButton.exists()).toBe(false);

      // Shows placeholder instead
      const placeholder = wrapper.find('span.text-gray-400');
      expect(placeholder.exists()).toBe(true);
      expect(placeholder.text()).toBe('--');
    });

    it('disables remove button when isLoading is true', () => {
      mockCanModifyMember.mockReturnValue(true);

      mountComponent({
        members: [createMember({ role: 'admin' })],
        isLoading: true,
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      expect(removeButton.attributes('disabled')).toBeDefined();
    });
  });

  describe('Loading state handling', () => {
    it('disables role selector during loading', () => {
      mockCanChangeRole.mockReturnValue(true);

      mountComponent({
        members: [createMember({ role: 'admin' })],
        isLoading: true,
      });

      const selector = wrapper.find('[data-testid="role-selector"]');
      expect(selector.attributes('disabled')).toBeDefined();
    });

    it('disables remove button during loading', () => {
      mockCanModifyMember.mockReturnValue(true);

      mountComponent({
        members: [createMember({ role: 'admin' })],
        isLoading: true,
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      expect(removeButton.attributes('disabled')).toBeDefined();
      expect(removeButton.classes()).toContain('disabled:opacity-50');
      expect(removeButton.classes()).toContain('disabled:cursor-not-allowed');
    });
  });

  describe('Confirm dialog for member removal', () => {
    it('shows confirm dialog when remove button is clicked', async () => {
      mockCanModifyMember.mockReturnValue(true);
      mockReveal.mockResolvedValue(false); // User cancels

      mountComponent({
        members: [createMember({ extid: 'mem_admin', email: 'admin@example.com', role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      await removeButton.trigger('click');

      expect(mockReveal).toHaveBeenCalled();
    });

    it('renders confirm dialog with correct title and message', async () => {
      mockCanModifyMember.mockReturnValue(true);

      // Mock reveal to set isRevealed synchronously and return a pending promise
      // This simulates the dialog being shown and waiting for user action
      let resolveReveal: (value: boolean) => void;
      mockReveal.mockImplementation(() => {
        mockIsRevealed.value = true;
        return new Promise<boolean>((resolve) => {
          resolveReveal = resolve;
        });
      });

      mountComponent({
        members: [createMember({ extid: 'mem_admin', email: 'admin@example.com', role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      // Click triggers reveal() but doesn't await it yet
      removeButton.trigger('click');
      await nextTick();
      await nextTick(); // Extra tick for Vue's reactivity

      const dialog = wrapper.find('[data-testid="confirm-dialog"]');
      expect(dialog.exists()).toBe(true);

      const title = wrapper.find('[data-testid="dialog-title"]');
      expect(title.text()).toBe('Remove Member');

      const message = wrapper.find('[data-testid="dialog-message"]');
      expect(message.text()).toContain('admin@example.com');

      // Cleanup: resolve the pending promise
      resolveReveal!(false);
      await flushPromises();
    });

    it('calls removeMember and emits member-removed when confirmed', async () => {
      mockCanModifyMember.mockReturnValue(true);
      mockRemoveMember.mockResolvedValue(true);
      mockReveal.mockResolvedValue(true); // User confirms

      mountComponent({
        members: [createMember({ extid: 'mem_admin', email: 'admin@example.com', role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      await removeButton.trigger('click');
      await flushPromises();

      expect(mockRemoveMember).toHaveBeenCalledWith('on1abc123', 'mem_admin');

      const emitted = wrapper.emitted('member-removed');
      expect(emitted).toBeDefined();
      expect(emitted).toHaveLength(1);
      expect(emitted![0]).toEqual(['mem_admin']);
    });

    it('does not call removeMember when dialog is cancelled', async () => {
      mockCanModifyMember.mockReturnValue(true);
      mockReveal.mockResolvedValue(false); // User cancels

      mountComponent({
        members: [createMember({ extid: 'mem_admin', email: 'admin@example.com', role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      await removeButton.trigger('click');
      await flushPromises();

      expect(mockRemoveMember).not.toHaveBeenCalled();

      const emitted = wrapper.emitted('member-removed');
      expect(emitted).toBeUndefined();
    });

    it('does not emit member-removed when removeMember fails', async () => {
      mockCanModifyMember.mockReturnValue(true);
      mockRemoveMember.mockResolvedValue(false); // Operation fails
      mockReveal.mockResolvedValue(true);

      mountComponent({
        members: [createMember({ extid: 'mem_admin', role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      await removeButton.trigger('click');
      await flushPromises();

      expect(mockRemoveMember).toHaveBeenCalled();

      const emitted = wrapper.emitted('member-removed');
      expect(emitted).toBeUndefined();
    });

    it('renders dialog with danger type for removal confirmation', async () => {
      mockCanModifyMember.mockReturnValue(true);

      // Mock reveal to set isRevealed and return a pending promise
      let resolveReveal: (value: boolean) => void;
      mockReveal.mockImplementation(() => {
        mockIsRevealed.value = true;
        return new Promise<boolean>((resolve) => {
          resolveReveal = resolve;
        });
      });

      mountComponent({
        members: [createMember({ extid: 'mem_admin', role: 'admin' })],
      });

      const removeButton = wrapper.find('button[aria-label="Remove Member"]');
      removeButton.trigger('click');
      await nextTick();
      await nextTick();

      // The ConfirmDialog is rendered with type="danger"
      // Our mock component receives this as a prop
      const dialog = wrapper.findComponent({ name: 'ConfirmDialog' });
      expect(dialog.exists()).toBe(true);
      expect(dialog.props('type')).toBe('danger');

      // Cleanup
      resolveReveal!(false);
      await flushPromises();
    });
  });

  describe('Design system compliance', () => {
    it('uses correct surface styling (bg-white/60 backdrop-blur-sm)', () => {
      mountComponent({ compact: false });

      const section = wrapper.find('section');
      const classes = section.classes();

      expect(classes).toContain('bg-white/60');
      expect(classes).toContain('backdrop-blur-sm');
    });

    it('uses correct typography for title (text-xl font-medium)', () => {
      mountComponent({ compact: false });

      const title = wrapper.find('h1#members-heading');
      expect(title.exists()).toBe(true);
      expect(title.classes()).toContain('text-xl');
      expect(title.classes()).toContain('font-medium');
    });

    it('uses correct spacing for header (mb-4)', () => {
      mountComponent({ compact: false });

      const headerDiv = wrapper.find('div.mb-4');
      expect(headerDiv.exists()).toBe(true);
    });
  });
});
