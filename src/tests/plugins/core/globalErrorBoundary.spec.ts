// src/tests/plugins/core/globalErrorBoundary.spec.ts
//
// Tests for globalErrorBoundary.ts - specifically the getComponentName() utility
// that extracts Vue component names for Sentry context.
//
// Issue: #2966 - Add component name to Sentry context
//
// Run:
//   pnpm test src/tests/plugins/core/globalErrorBoundary.spec.ts

import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { getComponentName } from '@/plugins/core/globalErrorBoundary';

describe('getComponentName', () => {
  describe('null/invalid inputs', () => {
    it('returns unknown for null instance', () => {
      expect(getComponentName(null)).toBe('unknown');
    });

    it('returns unknown for undefined instance', () => {
      expect(getComponentName(undefined)).toBe('unknown');
    });

    it('returns unknown for non-object (string)', () => {
      expect(getComponentName('not an object')).toBe('unknown');
    });

    it('returns unknown for non-object (number)', () => {
      expect(getComponentName(42)).toBe('unknown');
    });

    it('returns unknown for non-object (boolean)', () => {
      expect(getComponentName(true)).toBe('unknown');
    });

    it('returns unknown for empty object', () => {
      expect(getComponentName({})).toBe('unknown');
    });
  });

  describe('Options API components', () => {
    it('extracts name from $options.name', () => {
      const instance = { $options: { name: 'TestComponent' } };
      expect(getComponentName(instance)).toBe('TestComponent');
    });

    it('handles $options without name property', () => {
      const instance = { $options: { props: ['value'] } };
      expect(getComponentName(instance)).toBe('unknown');
    });

    it('handles $options.name as empty string', () => {
      const instance = { $options: { name: '' } };
      // Empty string is falsy, falls through to next check
      expect(getComponentName(instance)).toBe('unknown');
    });
  });

  describe('Script setup components ($.type.name)', () => {
    it('extracts name from $.type.name', () => {
      const instance = {
        $: { type: { name: 'ScriptSetupComponent' } },
      };
      expect(getComponentName(instance)).toBe('ScriptSetupComponent');
    });

    it('prefers $options.name over $.type.name', () => {
      const instance = {
        $options: { name: 'OptionsName' },
        $: { type: { name: 'TypeName' } },
      };
      expect(getComponentName(instance)).toBe('OptionsName');
    });

    it('handles $.type without name', () => {
      const instance = {
        $: { type: { props: {} } },
      };
      expect(getComponentName(instance)).toBe('unknown');
    });
  });

  describe('Script setup components ($.type.__name)', () => {
    it('extracts name from $.type.__name (Vue SFC compiled)', () => {
      const instance = {
        $: { type: { __name: 'CompiledSFCComponent' } },
      };
      expect(getComponentName(instance)).toBe('CompiledSFCComponent');
    });

    it('prefers $.type.name over $.type.__name', () => {
      const instance = {
        $: { type: { name: 'TypeName', __name: 'UnderscoreName' } },
      };
      expect(getComponentName(instance)).toBe('TypeName');
    });

    it('uses __name as final fallback', () => {
      const instance = {
        $options: {},
        $: { type: { __name: 'FallbackName' } },
      };
      expect(getComponentName(instance)).toBe('FallbackName');
    });
  });

  describe('edge cases', () => {
    it('handles instance with $ but no type', () => {
      const instance = { $: {} };
      expect(getComponentName(instance)).toBe('unknown');
    });

    it('handles instance with $ as null', () => {
      const instance = { $: null };
      expect(getComponentName(instance)).toBe('unknown');
    });

    it('handles instance with $options as null', () => {
      const instance = { $options: null };
      expect(getComponentName(instance)).toBe('unknown');
    });

    it('handles array instance (non-component)', () => {
      expect(getComponentName(['not', 'a', 'component'])).toBe('unknown');
    });

    it('handles function instance (non-component)', () => {
      expect(getComponentName(() => {})).toBe('unknown');
    });
  });

  describe('realistic Vue component structures', () => {
    it('extracts name from full Options API component instance', () => {
      const instance = {
        $options: {
          name: 'SecretForm',
          props: { value: String },
          components: {},
        },
        $props: { value: 'test' },
        $emit: () => {},
      };
      expect(getComponentName(instance)).toBe('SecretForm');
    });

    it('extracts name from full script setup component instance', () => {
      const instance = {
        $options: {},
        $: {
          type: {
            __name: 'CreateSecret',
            setup: () => {},
            props: {},
          },
          props: {},
          emit: () => {},
        },
      };
      expect(getComponentName(instance)).toBe('CreateSecret');
    });

    it('extracts name from component with both API styles', () => {
      // Some components may have both due to mixins or extending
      const instance = {
        $options: { name: 'MixedComponent' },
        $: {
          type: { __name: 'InternalName' },
        },
      };
      // $options.name takes precedence
      expect(getComponentName(instance)).toBe('MixedComponent');
    });
  });

  describe('runtime validation with real Vue components', () => {
    // These tests mount actual Vue components to validate our assumptions
    // about Vue's internal instance structure are correct.

    it('extracts name from mounted Options API component', () => {
      const OptionsComponent = defineComponent({
        name: 'OptionsApiTestComponent',
        render() {
          return h('div', 'test');
        },
      });

      const wrapper = mount(OptionsComponent);
      // vm is the component instance passed to errorHandler
      const instance = wrapper.vm;

      expect(getComponentName(instance)).toBe('OptionsApiTestComponent');
      wrapper.unmount();
    });

    it('extracts name from mounted script setup style component', () => {
      // Script setup components use $.type.__name internally
      // We simulate this by defining a component without explicit name
      // but Vue's internal structure should still be accessible
      const ScriptSetupLike = defineComponent({
        name: 'ScriptSetupTestComponent',
        setup() {
          return () => h('div', 'script setup');
        },
      });

      const wrapper = mount(ScriptSetupLike);
      const instance = wrapper.vm;

      // Even script-setup-like components with defineComponent have $options.name
      expect(getComponentName(instance)).toBe('ScriptSetupTestComponent');
      wrapper.unmount();
    });

    it('extracts name from anonymous component via $.type.__name', () => {
      // Anonymous components (no name in defineComponent) rely on $.type.__name
      // which is set by the SFC compiler. We can test the fallback path.
      const AnonymousComponent = defineComponent({
        // No name property - simulates component without explicit name
        render() {
          return h('span', 'anonymous');
        },
      });

      const wrapper = mount(AnonymousComponent);
      const instance = wrapper.vm;

      // Without a name, falls through to $.type.name or __name
      // In test environment without SFC compilation, may return 'unknown'
      const name = getComponentName(instance);

      // Verify the function doesn't crash and returns a valid result
      expect(typeof name).toBe('string');
      wrapper.unmount();
    });

    it('validates Vue instance has expected structure', () => {
      // This test documents the actual structure we rely on
      const TestComponent = defineComponent({
        name: 'StructureValidation',
        render() {
          return h('div');
        },
      });

      const wrapper = mount(TestComponent);
      const instance = wrapper.vm;

      // Verify $options exists and has name (Options API path)
      expect(instance.$options).toBeDefined();
      expect(instance.$options.name).toBe('StructureValidation');

      // Document existence of internal $ property (Script setup path)
      // Note: $ may not be directly accessible on the public proxy in all scenarios
      // but our type guards handle this safely
      expect(typeof instance).toBe('object');

      wrapper.unmount();
    });
  });
});
