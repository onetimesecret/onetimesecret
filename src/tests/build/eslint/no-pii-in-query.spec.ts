// src/tests/build/eslint/no-pii-in-query.spec.ts

/**
 * RuleTester coverage for the custom ots/no-pii-in-query ESLint rule. The rule
 * flags PII keys written into a `query` object literal; dynamically-assembled
 * query objects are intentionally out of a static rule's reach (the runtime
 * navigation guard covers those).
 *
 * RuleTester.run registers its own describe/it blocks via the (global) test
 * framework, so it must be invoked at the top level — not wrapped in an it().
 */

import { RuleTester } from 'eslint';
import rule from '@/build/eslint/no-pii-in-query';

const ruleTester = new RuleTester({
  languageOptions: { ecmaVersion: 'latest', sourceType: 'module' },
});

ruleTester.run('ots/no-pii-in-query', rule, {
  valid: [
    // Non-PII query keys are fine.
    { code: `router.push({ path: '/x', query: { product: 'identity', interval: 'month' } });` },
    { code: `router.push({ path: '/x', query: { redirect: '/dashboard' } });` },
    // Email handed over via state, not the query — the sanctioned pattern.
    { code: `router.push({ path: '/check-email', state: { checkEmailAddress: email } });` },
    // Dynamically-assembled query is out of static reach (no literal PII key).
    { code: `const q = {}; q.email = e; router.push({ path: '/x', query: q });` },
    // A bare object with an email but no enclosing `query` key is not our concern.
    { code: `const payload = { email: 'a@b.com' };` },
  ],
  invalid: [
    {
      code: `router.push({ path: '/x', query: { email } });`,
      errors: [{ messageId: 'piiInQuery', data: { key: 'email' } }],
    },
    {
      code: `router.push({ path: '/x', query: { email: e, product: 'p' } });`,
      errors: [{ messageId: 'piiInQuery' }],
    },
    {
      code: `const to = { path: '/signup', query: { email: 'a@b.com', token: 't' } };`,
      errors: [{ messageId: 'piiInQuery' }, { messageId: 'piiInQuery' }],
    },
    {
      // String-literal key is caught too.
      code: `router.push({ query: { 'code': c } });`,
      errors: [{ messageId: 'piiInQuery', data: { key: 'code' } }],
    },
  ],
});
