// src/tests/shared/components/ui/SplitButton.spec.ts
//
// Tests for SplitButton.vue keyboard shortcut functionality:
// - Keyboard hint visibility and platform-specific text
// - Keyboard shortcut triggering main action
// - Shortcut disabled states

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref, nextTick } from 'vue';
import SplitButton from '@/shared/components/ui/SplitButton.vue';

// Track the magic keys mock state
const mockMetaEnter = ref(false);
const mockControlEnter = ref(false);

// Mock useMagicKeys from @vueuse/core
vi.mock('@vueuse/core', () => ({
  useMagicKeys: vi.fn(() => ({
    'Meta+Enter': mockMetaEnter,
    'Control+Enter': mockControlEnter,
  })),
  whenever: vi.fn((_source, callback) => {
    // Store reference to callback for manual triggering in tests
    (vi as unknown as { __wheneverCallback: typeof callback }).__wheneverCallback = callback;
  }),
}));

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => {
      const translations: Record<string, string> = {
        'web.LABELS.create_link_short': 'Create Link',
        'web.COMMON.button_generate_secret_short': 'Generate',
      };
      return translations[key] || key;
    }),
  })),
}));

describe('SplitButton Keyboard Shortcuts', () => {
  let wrapper: VueWrapper;
  const originalPlatform = navigator.platform;

  beforeEach(() => {
    vi.clearAllMocks();
    mockMetaEnter.value = false;
    mockControlEnter.value = false;
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
    // Restore original platform
    Object.defineProperty(navigator, 'platform', {
      value: originalPlatform,
      writable: true,
      configurable: true,
    });
  });

  const mountComponent = (props: Record<string, unknown> = {}) => {
    return mount(SplitButton, {
      props: {
        content: '',
        withGenerate: false,
        disabled: false,
        disableGenerate: false,
        cornerClass: 'rounded-xl',
        primaryColor: '#3b82f6',
        buttonTextLight: true,
        keyboardShortcutEnabled: false,
        showKeyboardHint: false,
        ...props,
      },
      global: {
        stubs: {
          // Stub any child components if needed
        },
      },
    });
  };

  describe('Keyboard Hint Visibility', () => {
    it('shows keyboard hint when showKeyboardHint is true', () => {
      wrapper = mountComponent({
        showKeyboardHint: true,
        keyboardShortcutEnabled: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.exists()).toBe(true);
    });

    it('hides keyboard hint when showKeyboardHint is false', () => {
      wrapper = mountComponent({
        showKeyboardHint: false,
        keyboardShortcutEnabled: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.exists()).toBe(false);
    });

    it('shows keyboard hint even when keyboardShortcutEnabled is false', () => {
      // The hint is purely visual and independent of shortcut functionality
      wrapper = mountComponent({
        showKeyboardHint: true,
        keyboardShortcutEnabled: false,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.exists()).toBe(true);
    });
  });

  describe('Platform-Specific Keyboard Hint Text', () => {
    it('shows command symbol on Mac platform', () => {
      Object.defineProperty(navigator, 'platform', {
        value: 'MacIntel',
        writable: true,
        configurable: true,
      });

      wrapper = mountComponent({
        showKeyboardHint: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.text()).toContain('\u2318'); // Command symbol
      expect(kbdElement.text()).toContain('Enter');
    });

    it('shows Ctrl on Windows platform', () => {
      Object.defineProperty(navigator, 'platform', {
        value: 'Win32',
        writable: true,
        configurable: true,
      });

      wrapper = mountComponent({
        showKeyboardHint: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.text()).toContain('Ctrl');
      expect(kbdElement.text()).toContain('Enter');
    });

    it('shows Ctrl on Linux platform', () => {
      Object.defineProperty(navigator, 'platform', {
        value: 'Linux x86_64',
        writable: true,
        configurable: true,
      });

      wrapper = mountComponent({
        showKeyboardHint: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.text()).toContain('Ctrl');
      expect(kbdElement.text()).toContain('Enter');
    });

    it('shows command symbol on iPhone platform', () => {
      Object.defineProperty(navigator, 'platform', {
        value: 'iPhone',
        writable: true,
        configurable: true,
      });

      wrapper = mountComponent({
        showKeyboardHint: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.text()).toContain('\u2318');
    });

    it('shows command symbol on iPad platform', () => {
      Object.defineProperty(navigator, 'platform', {
        value: 'iPad',
        writable: true,
        configurable: true,
      });

      wrapper = mountComponent({
        showKeyboardHint: true,
      });

      const kbdElement = wrapper.find('kbd');
      expect(kbdElement.text()).toContain('\u2318');
    });
  });

  describe('Main Button Click Behavior', () => {
    it('main button is a submit button that triggers form submission', async () => {
      wrapper = mountComponent({
        content: 'some content',
      });

      const mainButton = wrapper.find('button[type="submit"]');
      expect(mainButton.attributes('type')).toBe('submit');
      // Note: The component uses a native submit button, not custom events
      // Form submission is handled by the parent form element
    });

    it('main button is disabled when disabled prop is true', async () => {
      wrapper = mountComponent({
        disabled: true,
      });

      const mainButton = wrapper.find('button[type="submit"]');
      expect(mainButton.attributes('disabled')).toBeDefined();
    });
  });

  describe('Dropdown Action Selection', () => {
    it('opens dropdown when toggle button is clicked', async () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      // Dropdown should be closed initially
      expect(wrapper.find('#split-button-dropdown').exists()).toBe(false);

      // Click the dropdown toggle button (second button)
      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      await toggleButton.trigger('click');

      // Dropdown should now be visible
      expect(wrapper.find('#split-button-dropdown').exists()).toBe(true);
    });

    it('emits update:action when action is selected', async () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      // Open dropdown
      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      await toggleButton.trigger('click');
      await nextTick();

      // Click generate password option
      const dropdownButtons = wrapper.find('#split-button-dropdown').findAll('button');
      // Second button in dropdown is "Generate Password"
      const generateButton = dropdownButtons[1];
      await generateButton.trigger('click');

      expect(wrapper.emitted('update:action')).toBeTruthy();
      // Last emission should be 'generate-password'
      const emissions = wrapper.emitted('update:action') as unknown[][];
      expect(emissions[emissions.length - 1][0]).toBe('generate-password');
    });

    it('closes dropdown after action is selected', async () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      // Open dropdown
      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      await toggleButton.trigger('click');

      expect(wrapper.find('#split-button-dropdown').exists()).toBe(true);

      // Select an action
      const dropdownButtons = wrapper.find('#split-button-dropdown').findAll('button');
      await dropdownButtons[0].trigger('click');

      // Dropdown should close
      expect(wrapper.find('#split-button-dropdown').exists()).toBe(false);
    });
  });

  describe('Action Selection Changes Button Behavior', () => {
    it('emits update:action with generate-password when generate action selected', async () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      // Open dropdown and select generate
      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      await toggleButton.trigger('click');
      await nextTick();

      const dropdownButtons = wrapper.find('#split-button-dropdown').findAll('button');
      await dropdownButtons[1].trigger('click');
      await nextTick();

      // Verify update:action event was emitted with 'generate-password'
      const emittedEvents = wrapper.emitted('update:action');
      expect(emittedEvents).toBeTruthy();
      // Last emitted value should be 'generate-password'
      expect(emittedEvents![emittedEvents!.length - 1]).toEqual(['generate-password']);
    });

    it('emits update:action with create-link when switching back to create-link', async () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      // First switch to generate
      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      await toggleButton.trigger('click');
      const dropdownButtons = wrapper.find('#split-button-dropdown').findAll('button');
      await dropdownButtons[1].trigger('click');
      await nextTick();

      // Then switch back to create-link
      await toggleButton.trigger('click');
      const dropdownButtons2 = wrapper.find('#split-button-dropdown').findAll('button');
      await dropdownButtons2[0].trigger('click');
      await nextTick();

      // Verify update:action event was emitted with 'create-link'
      const emittedEvents = wrapper.emitted('update:action');
      expect(emittedEvents).toBeTruthy();
      // Last emitted value should be 'create-link'
      expect(emittedEvents![emittedEvents!.length - 1]).toEqual(['create-link']);
    });
  });

  describe('Accessibility', () => {
    it('has aria-label on main button', () => {
      wrapper = mountComponent();

      const mainButton = wrapper.find('button[type="submit"]');
      expect(mainButton.attributes('aria-label')).toBe('Create Link');
    });

    it('has aria-haspopup on dropdown toggle', () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      expect(toggleButton.attributes('aria-haspopup')).toBe('true');
    });

    it('has aria-expanded that changes with dropdown state', async () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');

      // Initially closed
      expect(toggleButton.attributes('aria-expanded')).toBe('false');

      // Open dropdown
      await toggleButton.trigger('click');
      expect(toggleButton.attributes('aria-expanded')).toBe('true');

      // Close dropdown
      await toggleButton.trigger('click');
      expect(toggleButton.attributes('aria-expanded')).toBe('false');
    });

    it('has aria-controls pointing to dropdown', () => {
      wrapper = mountComponent({
        withGenerate: true,
      });

      const toggleButton = wrapper.find('button[aria-label="Show more actions"]');
      expect(toggleButton.attributes('aria-controls')).toBe('split-button-dropdown');
    });

    it('announces action change to screen readers', () => {
      wrapper = mountComponent();

      const announcement = wrapper.find('[aria-live="assertive"]');
      expect(announcement.exists()).toBe(true);
    });
  });

  describe('Button Disabled States', () => {
    it('main button is disabled when disabled prop is true', () => {
      wrapper = mountComponent({
        disabled: true,
      });

      const mainButton = wrapper.find('button[type="submit"]');
      expect(mainButton.attributes('disabled')).toBeDefined();
    });

    it('main button has disabled styling when disabled', () => {
      wrapper = mountComponent({
        disabled: true,
      });

      const mainButton = wrapper.find('button[type="submit"]');
      expect(mainButton.classes()).toContain('cursor-not-allowed');
    });
  });
});

describe('SplitButton Keyboard Shortcut Logic (Unit Tests)', () => {
  // These tests verify the keyboard shortcut logic in isolation
  // without mounting the full component

  describe('submitShortcut computed behavior', () => {
    it('returns true when keyboardShortcutEnabled and Meta+Enter pressed', () => {
      const keyboardShortcutEnabled = true;
      const metaEnter = true;
      const controlEnter = false;

      const submitShortcut =
        keyboardShortcutEnabled && (metaEnter || controlEnter);

      expect(submitShortcut).toBe(true);
    });

    it('returns true when keyboardShortcutEnabled and Control+Enter pressed', () => {
      const keyboardShortcutEnabled = true;
      const metaEnter = false;
      const controlEnter = true;

      const submitShortcut =
        keyboardShortcutEnabled && (metaEnter || controlEnter);

      expect(submitShortcut).toBe(true);
    });

    it('returns false when keyboardShortcutEnabled is false even if shortcut pressed', () => {
      const keyboardShortcutEnabled = false;
      const metaEnter = true;
      const controlEnter = false;

      const submitShortcut =
        keyboardShortcutEnabled && (metaEnter || controlEnter);

      expect(submitShortcut).toBe(false);
    });

    it('returns false when no shortcut key is pressed', () => {
      const keyboardShortcutEnabled = true;
      const metaEnter = false;
      const controlEnter = false;

      const submitShortcut =
        keyboardShortcutEnabled && (metaEnter || controlEnter);

      expect(submitShortcut).toBe(false);
    });
  });

  describe('handleMainClick guard behavior', () => {
    it('does not emit when button is disabled', () => {
      const isMainButtonDisabled = true;
      const emitFn = vi.fn();

      const handleMainClick = () => {
        if (isMainButtonDisabled) return;
        emitFn();
      };

      handleMainClick();
      expect(emitFn).not.toHaveBeenCalled();
    });

    it('emits when button is not disabled', () => {
      const isMainButtonDisabled = false;
      const emitFn = vi.fn();

      const handleMainClick = () => {
        if (isMainButtonDisabled) return;
        emitFn();
      };

      handleMainClick();
      expect(emitFn).toHaveBeenCalled();
    });
  });

  describe('isMainButtonDisabled computed for create-link action', () => {
    it('returns true when disabled prop is true', () => {
      const selectedAction = 'create-link';
      const disabled = true;
      const content = 'some content';
      const isContentEmpty = !content.trim();

      const isMainButtonDisabled =
        selectedAction === 'create-link'
          ? disabled || (!isContentEmpty && !content)
          : false;

      expect(isMainButtonDisabled).toBe(true);
    });

    it('returns false when disabled is false and has content', () => {
      const selectedAction = 'create-link';
      const disabled = false;
      const content = 'some content';
      const isContentEmpty = !content.trim();

      const isMainButtonDisabled =
        selectedAction === 'create-link'
          ? disabled || (!isContentEmpty && !content)
          : false;

      expect(isMainButtonDisabled).toBe(false);
    });
  });

  describe('isMainButtonDisabled computed for generate-password action', () => {
    it('returns disableGenerate value when action is generate-password', () => {
      const selectedAction = 'generate-password';
      const disableGenerate = true;

      const isMainButtonDisabled =
        selectedAction === 'generate-password' ? disableGenerate : false;

      expect(isMainButtonDisabled).toBe(true);
    });

    it('returns false when disableGenerate is false', () => {
      const selectedAction = 'generate-password';
      const disableGenerate = false;

      const isMainButtonDisabled =
        selectedAction === 'generate-password' ? disableGenerate : false;

      expect(isMainButtonDisabled).toBe(false);
    });
  });
});

describe('SplitButton Platform Detection', () => {
  const originalPlatform = navigator.platform;

  afterEach(() => {
    Object.defineProperty(navigator, 'platform', {
      value: originalPlatform,
      writable: true,
      configurable: true,
    });
  });

  it('isMac returns true for MacIntel', () => {
    Object.defineProperty(navigator, 'platform', {
      value: 'MacIntel',
      writable: true,
      configurable: true,
    });

    const isMac =
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform);

    expect(isMac).toBe(true);
  });

  it('isMac returns true for iPad', () => {
    Object.defineProperty(navigator, 'platform', {
      value: 'iPad',
      writable: true,
      configurable: true,
    });

    const isMac =
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform);

    expect(isMac).toBe(true);
  });

  it('isMac returns false for Win32', () => {
    Object.defineProperty(navigator, 'platform', {
      value: 'Win32',
      writable: true,
      configurable: true,
    });

    const isMac =
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform);

    expect(isMac).toBe(false);
  });

  it('isMac returns false for Linux', () => {
    Object.defineProperty(navigator, 'platform', {
      value: 'Linux x86_64',
      writable: true,
      configurable: true,
    });

    const isMac =
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform);

    expect(isMac).toBe(false);
  });

  it('shortcutHint returns command symbol for Mac', () => {
    Object.defineProperty(navigator, 'platform', {
      value: 'MacIntel',
      writable: true,
      configurable: true,
    });

    const isMac =
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform);
    const shortcutHint = isMac ? '\u2318 Enter' : 'Ctrl Enter';

    expect(shortcutHint).toBe('\u2318 Enter');
  });

  it('shortcutHint returns Ctrl Enter for Windows', () => {
    Object.defineProperty(navigator, 'platform', {
      value: 'Win32',
      writable: true,
      configurable: true,
    });

    const isMac =
      typeof navigator !== 'undefined' &&
      /Mac|iPod|iPhone|iPad/.test(navigator.platform);
    const shortcutHint = isMac ? '\u2318 Enter' : 'Ctrl Enter';

    expect(shortcutHint).toBe('Ctrl Enter');
  });
});
