// src/schemas/config/runtime.spec.ts

import { describe, expect, it } from 'vitest';
import { configSchema, type Config } from '@/schemas/config/runtime';
import { configSchema as staticConfigSchema } from '@/schemas/config/static';
import { configSchema as mutableConfigSchema } from '@/schemas/config/mutable';

describe('runtime configuration schema', () => {
  describe('schema merging', () => {
    it('contains all static config fields', () => {
      const staticFields = Object.keys(staticConfigSchema.shape);
      const runtimeFields = Object.keys(configSchema.shape);

      staticFields.forEach((field) => {
        expect(runtimeFields).toContain(field);
      });
    });

    it('contains all mutable config fields', () => {
      const mutableFields = Object.keys(mutableConfigSchema.shape);
      const runtimeFields = Object.keys(configSchema.shape);

      mutableFields.forEach((field) => {
        expect(runtimeFields).toContain(field);
      });
    });

    it('static config takes precedence over mutable config for conflicting keys', () => {
      // Both schemas define 'mail' - static should override mutable
      const staticMailShape = staticConfigSchema.shape.mail;
      const mutableMailShape = mutableConfigSchema.shape.mail;
      const runtimeMailShape = configSchema.shape.mail;

      expect(runtimeMailShape).toBe(staticMailShape);
      expect(runtimeMailShape).not.toBe(mutableMailShape);
    });
  });

  describe('validation', () => {
    it('validates a complete valid configuration', () => {
      const validConfig: Config = {
        // Static fields (required)
        site: {
          host: 'localhost',
          ssl: false,
          secret: 'test-secret',
          authentication: {
            enabled: false,
            colonels: [],
            autoverify: false,
          },
          authenticity: {
            enabled: false,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
          },
        },
        mail: {
          connection: {
            mode: 'smtp',
            host: 'localhost',
            port: 587,
          },
          validation: {},
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
          fallback_locale: {},
          locales: [],
          incomplete: [],
        },
        development: {},
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: [],
          freeze_app: false,
        },

        // Mutable fields (optional)
        ui: {
          enabled: true,
        },
        api: {
          enabled: true,
        },
        secret_options: {
          default_ttl: 3600,
          ttl_options: [300, 3600, 86400],
        },
        features: {
          incoming: {
            enabled: true,
          },
        },
        limits: {
          create_secret: 10,
        },
      };

      const result = configSchema.safeParse(validConfig);
      expect(result.success).toBe(true);
    });

    it('validates minimal configuration with only required static fields', () => {
      const minimalConfig = {
        site: {
          host: 'localhost',
          ssl: false,
          secret: 'test-secret',
          authentication: {
            enabled: false,
            colonels: [],
            autoverify: false,
          },
          authenticity: {
            enabled: false,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
          },
        },
        mail: {
          connection: {
            mode: 'smtp',
            host: 'localhost',
            port: 587,
          },
          validation: {},
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
          fallback_locale: {},
          locales: [],
          incomplete: [],
        },
        development: {},
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: [],
          freeze_app: false,
        },
      };

      const result = configSchema.safeParse(minimalConfig);
      expect(result.success).toBe(true);
    });

    it('fails validation when required static fields are missing', () => {
      const incompleteConfig = {
        // Missing required static fields like site, storage, etc.
        ui: {
          theme: 'default',
        },
        api: {
          enabled: true,
        },
      };

      const result = configSchema.safeParse(incompleteConfig);
      expect(result.success).toBe(false);
    });

    it('allows mutable fields to be omitted', () => {
      const configWithoutMutableFields = {
        site: {
          host: 'localhost',
          ssl: false,
          secret: 'test-secret',
          authentication: {
            enabled: false,
            colonels: [],
            autoverify: false,
          },
          authenticity: {
            enabled: false,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
          },
        },
        mail: {
          connection: {
            mode: 'smtp',
            host: 'localhost',
            port: 587,
          },
          validation: {},
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
          fallback_locale: {},
          locales: [],
          incomplete: [],
        },
        development: {},
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: [],
          freeze_app: false,
        },
        // No mutable fields
      };

      const result = configSchema.safeParse(configWithoutMutableFields);
      expect(result.success).toBe(true);
    });
  });

  describe('mail field precedence', () => {
    it('uses static mail schema structure', () => {
      const testConfig = {
        site: {
          host: 'localhost',
          ssl: false,
          secret: 'test-secret',
          authentication: {
            enabled: false,
            colonels: [],
            autoverify: false,
          },
          authenticity: {
            enabled: false,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
          },
        },
        mail: {
          // Static mail structure requires 'connection' and 'validation'
          connection: {
            mode: 'smtp',
            host: 'localhost',
            port: 587,
          },
          validation: {
            defaults: {
              default_validation_type: 'mx',
              verifier_email: 'test@example.com',
              verifier_domain: 'example.com',
            },
          },
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
          fallback_locale: {},
          locales: [],
          incomplete: [],
        },
        development: {},
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: [],
          freeze_app: false,
        },
      };

      const result = configSchema.safeParse(testConfig);
      expect(result.success).toBe(true);
    });

    it('rejects mutable mail structure when using runtime schema', () => {
      const testConfig = {
        site: {
          host: 'localhost',
          ssl: false,
          secret: 'test-secret',
          authentication: {
            enabled: false,
            colonels: [],
            autoverify: false,
          },
          authenticity: {
            enabled: false,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
          },
        },
        mail: {
          // Mutable mail structure has different validation shape
          validation: {
            recipients: {
              default_validation_type: 'mx',
              verifier_email: 'test@example.com',
              verifier_domain: 'example.com',
            },
            accounts: {
              default_validation_type: 'mx',
              verifier_email: 'test@example.com',
              verifier_domain: 'example.com',
            },
          },
          // Missing required 'connection' from static schema
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
          fallback_locale: {},
          locales: [],
          incomplete: [],
        },
        development: {},
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: [],
          freeze_app: false,
        },
      };

      const result = configSchema.safeParse(testConfig);
      expect(result.success).toBe(false);
      expect(result.error?.issues).toContainEqual(
        expect.objectContaining({
          path: ['mail', 'connection'],
          code: 'invalid_type',
        })
      );
    });
  });

  describe('type inference', () => {
    it('infers correct type from merged schema', () => {
      // This test ensures TypeScript types are correctly inferred
      const config: Config = {
        // Static fields
        site: {
          host: 'localhost',
          ssl: false,
          secret: 'test-secret',
          authentication: {
            enabled: false,
            colonels: [],
            autoverify: false,
          },
          authenticity: {
            enabled: false,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
          },
        },
        mail: {
          connection: {
            mode: 'smtp',
            host: 'localhost',
            port: 587,
          },
          validation: {},
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
          fallback_locale: {},
          locales: [],
          incomplete: [],
        },
        development: {},
        experimental: {
          allow_nil_global_secret: false,
          rotated_secrets: [],
          freeze_app: false,
        },

        // Mutable fields (should all be optional)
        ui: {
          enabled: true,
        },
        api: {
          enabled: true,
        },
      };

      // Verify the config can be parsed
      const result = configSchema.parse(config);

      // Since Zod applies defaults, we can't expect exact equality
      // Instead, verify that our input values are preserved
      expect(result.site.host).toBe(config.site.host);
      expect(result.ui?.enabled).toBe(config.ui?.enabled);
      expect(result.api?.enabled).toBe(config.api?.enabled);

      // Type-level test - these should not cause TypeScript errors
      expect(typeof result.site.host).toBe('string');
      expect(typeof result.ui?.enabled).toBe('boolean');
      expect(result.api?.enabled).toBe(true);
    });
  });
});
