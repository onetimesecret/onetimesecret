// src/build/eslint/no-pii-in-query.ts

/**
 * ESLint Rule: no-pii-in-query
 *
 * Flags personally-identifiable keys (email, token, …) written into a `query`
 * object literal — e.g. `router.push({ path, query: { email } })` or
 * `<router-link :to="{ query: { email } }">`.
 *
 * A URL leaks out of the app through browser history, bfcache, the `Referer`
 * header, proxy/CDN access logs and Sentry. PII must instead be handed to the
 * destination via router history `state`, which never enters the URL.
 *
 * This is the author-time complement to the runtime diagnostics scrubber and
 * the dev-only navigation guard (src/router/piiQueryGuard.ts). It catches the
 * naive inline shape at lint/PR time. Dynamically-assembled query objects
 * (`const q = {}; q.email = …`) are out of a static rule's reach — the runtime
 * guard covers those.
 *
 * @see src/utils/pii.ts
 * @see src/router/README.md ("Query-string policy")
 * @see docs/specs/issue-3424-disclosure-matrix.html (finding F6)
 */

import type { Rule } from 'eslint';
import type { Property } from 'estree';

/**
 * PII query keys. Kept in sync (by hand) with PII_QUERY_KEYS in src/utils/pii.ts
 * — this rule runs at lint time in Node and cannot resolve the `@/` alias, so it
 * cannot import that module.
 */
const PII_QUERY_KEYS = ['email', 'password', 'token', 'key', 'code'];

/** Extract the static string name of an object-literal property key, or null. */
function staticKeyName(prop: Property): string | null {
  if (prop.computed) return null;
  if (prop.key.type === 'Identifier') return prop.key.name;
  if (prop.key.type === 'Literal' && typeof prop.key.value === 'string') {
    return prop.key.value;
  }
  return null;
}

const rule: Rule.RuleModule = {
  meta: {
    type: 'problem',
    docs: {
      description:
        'Disallow PII keys (email, token, …) in a URL query object — pass PII via router history state instead',
      category: 'Security',
      recommended: true,
      url: 'https://owasp.org/www-community/vulnerabilities/Information_exposure_through_query_strings_in_url',
    },
    schema: [],
    messages: {
      piiInQuery:
        'PII key "{{key}}" must not travel in a URL query — it leaks via history, Referer, access logs and Sentry. Pass it through router history `state` instead. See src/router/README.md "Query-string policy".',
    },
  },

  create(context: Rule.RuleContext): Rule.RuleListener {
    return {
      /**
       * Match the `query` property of a route location object literal, then
       * inspect the keys of its object-literal value for PII.
       */
      Property(node: Property): void {
        const keyName = staticKeyName(node);
        if (keyName !== 'query') return;
        if (node.value.type !== 'ObjectExpression') return;

        for (const prop of node.value.properties) {
          if (prop.type !== 'Property') continue; // skip SpreadElement
          const innerKey = staticKeyName(prop);
          if (innerKey && PII_QUERY_KEYS.includes(innerKey)) {
            context.report({
              node: prop,
              messageId: 'piiInQuery',
              data: { key: innerKey },
            });
          }
        }
      },
    };
  },
};

export default rule;
