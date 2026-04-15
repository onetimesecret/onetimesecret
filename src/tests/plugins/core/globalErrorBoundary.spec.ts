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
});
