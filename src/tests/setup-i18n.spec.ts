import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { createTestI18n } from './setup';

const TranslationProbe = defineComponent({
  setup() {
    const { t } = useI18n();
    return () => h('span', t('common.submit'));
  },
});

describe('component test i18n installation', () => {
  it('renders raw keys without registration warnings on repeated explicit mounts', () => {
    const warn = vi.spyOn(console, 'warn');

    try {
      for (let index = 0; index < 3; index++) {
        const wrapper = mount(TranslationProbe, {
          global: { plugins: [createTestI18n()] },
        });

        try {
          expect(wrapper.text()).toBe('common.submit');
        } finally {
          wrapper.unmount();
        }
      }

      expect(warn).not.toHaveBeenCalled();
    } finally {
      warn.mockRestore();
    }
  });
});
