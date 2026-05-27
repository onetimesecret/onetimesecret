// src/tests/schemas/shapes/config/storage.spec.ts
//
// Coverage for the storage shape — Redis URI default, per-database
// number bounds (0..15), and the wrapper `storage.db.connection.url`
// default.

import { describe, it, expect } from 'vitest';
import {
  redisDbsSchema,
  redisSchema,
  storageSchema,
} from '@/schemas/contracts/config/section/storage';
import {
  redisDbsShape,
  redisShape,
  storageShape,
} from '@/schemas/shapes/config/section/storage';

describe('redisDbsShape — db number defaults and bounds', () => {
  it('defaults every db field to 0 on empty input', () => {
    const result = redisDbsShape.parse({});
    expect(result.session).toBe(0);
    expect(result.custom_domain).toBe(0);
    expect(result.customer).toBe(0);
    expect(result.metadata).toBe(0);
    expect(result.secret).toBe(0);
    expect(result.feedback).toBe(0);
  });

  it.each([
    ['session', 0, true],
    ['session', 15, true],
    ['session', -1, false],
    ['session', 16, false],
    ['session', 7.5, false],
  ])('%s = %s accepted? %s', (field, value, accepted) => {
    const parse = () => redisDbsShape.parse({ [field]: value });
    if (accepted) {
      expect(parse).not.toThrow();
    } else {
      expect(parse).toThrow();
    }
  });

  it('contract accepts db numbers outside 0..15', () => {
    expect(() => redisDbsSchema.parse({ session: 16 })).not.toThrow();
    expect(() => redisDbsSchema.parse({ session: -1 })).not.toThrow();
  });
});

describe('redisShape — uri default', () => {
  it('defaults uri on empty input', () => {
    expect(redisShape.parse({}).uri).toBe('redis://127.0.0.1:6379');
  });

  it('contract leaves uri undefined', () => {
    expect(redisSchema.parse({}).uri).toBeUndefined();
  });

  it('applies dbs sub-tree defaults when nested', () => {
    const result = redisShape.parse({ dbs: {} });
    expect(result.dbs?.session).toBe(0);
  });

  it('rejects out-of-range dbs entries through the composed shape', () => {
    expect(() => redisShape.parse({ dbs: { session: 99 } })).toThrow();
  });
});

describe('storageShape — connection url default', () => {
  it('fills db.connection.url when the wrapper objects are present', () => {
    const result = storageShape.parse({ db: { connection: {} } });
    expect(result.db?.connection?.url).toBe('redis://localhost:6379');
  });

  it('contract leaves db.connection.url undefined', () => {
    const c = storageSchema.parse({ db: { connection: {} } });
    expect(c.db?.connection?.url).toBeUndefined();
  });

  it('preserves caller-supplied database_mapping passthrough', () => {
    const result = storageShape.parse({
      db: { connection: {}, database_mapping: { session: 1, customer: 2 } },
    });
    expect(result.db?.database_mapping).toEqual({ session: 1, customer: 2 });
  });
});
