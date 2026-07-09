// src/build/eslint/no-pii-in-query.ts

/**
 * ESLint Rule: no-pii-in-query
 *
 * Flags personally-identifiable keys (email, token, …) written into a `query`
 * object literal — e.g. `router.push({ path, query: { email } })` or, in a Vue
 * template, `<router-link :to="{ query: { email } }">`.
 *
 * A URL leaks out of the app through browser history, bfcache, the `Referer`
 * header, proxy/CDN access logs and Sentry. PII must instead be handed to the
 * destination via router history `state`, which never enters the URL.
 *
 * This is the author-time complement to the runtime diagnostics scrubber and
 * the dev-only navigation guard (src/router/piiQueryGuard.ts). It catches the
 * naive inline shape at lint/PR time, in both <script> and <template>.
 * Dynamically-assembled query objects (`const q = {}; q.email = …`) are out of
 * a static rule's reach — the runtime guard covers those.
 *
 * @see src/utils/pii.ts (the shared PII_QUERY_KEYS list)
 * @see src/router/README.md ("Query-string policy")
 * @see docs/specs/recipient-disclosure/recipient-disclosure-matrix.html (finding F6)
 */

import type { Rule } from 'eslint';
import type { Property } from 'estree';

// Single source of truth for the key list — imported (not re-declared) so the
// rule and the runtime helpers can never drift. pii.ts is dependency-free, so
// it resolves cleanly under the config's TS loader at lint time.
import { PII_QUERY_KEYS } from '../../utils/pii';

// `.includes` on the readonly tuple would reject an arbitrary string arg.
const PII_KEYS: readonly string[] = PII_QUERY_KEYS;

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
    /**
     * Match the `query` property of a route-location object literal, then
     * inspect the keys of its object-literal value for PII. Works on the plain
     * ESTree nodes produced in both <script> and (via vue-eslint-parser)
     * <template> expressions.
     */
    function checkQuery(node: Property): void {
      if (staticKeyName(node) !== 'query') return;
      if (node.value.type !== 'ObjectExpression') return;

      for (const prop of node.value.properties) {
        if (prop.type !== 'Property') continue; // skip SpreadElement
        const innerKey = staticKeyName(prop);
        if (innerKey && PII_KEYS.includes(innerKey)) {
          context.report({ node: prop, messageId: 'piiInQuery', data: { key: innerKey } });
        }
      }
    }

    const scriptVisitor: Rule.RuleListener = { Property: checkQuery };

    // In .vue files, template expressions live in a separate AST
    // (ast.templateBody) that plain node visitors never traverse;
    // vue-eslint-parser exposes defineTemplateBodyVisitor to hook it. It is
    // absent for plain .ts files, so guard for it and fall back to script-only.
    const sourceCode = context.sourceCode ?? context.getSourceCode();
    const services = sourceCode.parserServices as
      | {
          defineTemplateBodyVisitor?: (
            templateVisitor: Rule.RuleListener,
            scriptVisitor?: Rule.RuleListener
          ) => Rule.RuleListener;
        }
      | undefined;

    if (services?.defineTemplateBodyVisitor) {
      return services.defineTemplateBodyVisitor({ Property: checkQuery }, scriptVisitor);
    }
    return scriptVisitor;
  },
};

export default rule;
