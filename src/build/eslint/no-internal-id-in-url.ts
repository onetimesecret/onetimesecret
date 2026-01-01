// src/build/eslint/no-internal-id-in-url.ts

/**
 * ESLint Rule: no-internal-id-in-url
 *
 * Detects potential OWASP IDOR violations by flagging `.id` usage in URL contexts.
 * Part of the Opaque Identifier Pattern implementation.
 *
 * RULE: Use `.extid` for URLs and API paths, not `.id` or `.objid`
 *
 * @see src/types/identifiers.ts
 * @see docs/IDENTIFIER-REVIEW-CHECKLIST.md
 */

import type { Rule } from 'eslint';
import type { MemberExpression, TemplateLiteral, Literal, Node } from 'estree';

/**
 * URL context patterns that should use ExtId, not internal IDs
 *
 * Note: Patterns are designed to minimize false positives while catching
 * common URL construction patterns in Vue/TypeScript codebases.
 */
const URL_PATTERNS = [
  // Route paths (entity-specific)
  /\/org\//,
  /\/secret\//,
  /\/domain/,
  /\/customer/,
  /\/api\//,
  // Vue Router navigation methods
  /router\.push\s*\(/,
  /\$router\.push\s*\(/,
  /router\.replace\s*\(/,
  /\$router\.replace\s*\(/,
  // Navigation method calls (more specific than just "navigate")
  /\.navigate\s*\(/,
  /useRouter\(\).*\.push/,
  // HTML/Vue template URL attributes (more specific patterns)
  /\bhref\s*[:=]/,
  /:to\s*=/,
  /\bto\s*[:=]\s*["`']/,
];

/**
 * Property names that represent internal IDs (should not be in URLs)
 */
const INTERNAL_ID_PROPERTIES = ['id', 'objid', 'object_id', 'owner_id', 'organization_id'];

/**
 * Property names that are safe for URLs
 */
const EXTERNAL_ID_PROPERTIES = ['extid', 'external_id', 'ext_id'];

/**
 * Check if a node is within a URL context
 */
function isInUrlContext(node: Node, context: Rule.RuleContext): boolean {
  const sourceCode = context.sourceCode || context.getourceCode();
  const ancestors = sourceCode.getAncestors(node);

  for (const ancestor of ancestors) {
    // Check template literals
    if (ancestor.type === 'TemplateLiteral') {
      const source = sourceCode.getText(ancestor);
      if (URL_PATTERNS.some((pattern) => pattern.test(source))) {
        return true;
      }
    }

    // Check string concatenation
    if (ancestor.type === 'BinaryExpression' && ancestor.operator === '+') {
      const source = sourceCode.getText(ancestor);
      if (URL_PATTERNS.some((pattern) => pattern.test(source))) {
        return true;
      }
    }

    // Check function calls like router.push()
    if (ancestor.type === 'CallExpression') {
      if (ancestor.callee.type === 'MemberExpression') {
        const callee = ancestor.callee as MemberExpression;
        if (callee.property.type === 'Identifier') {
          const methodName = callee.property.name;
          if (['push', 'replace', 'navigate', 'go'].includes(methodName)) {
            return true;
          }
        }
      }
    }

    // Check object properties like { to: `/path/${entity.id}` }
    if (ancestor.type === 'Property') {
      if (ancestor.key.type === 'Identifier') {
        const keyName = ancestor.key.name;
        if (['to', 'href', 'path', 'url', 'route'].includes(keyName)) {
          return true;
        }
      }
    }
  }

  return false;
}

const rule: Rule.RuleModule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Disallow internal IDs (.id, .objid) in URL contexts - use .extid instead',
      category: 'Security',
      recommended: true,
      url: 'https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/05-Authorization_Testing/04-Testing_for_Insecure_Direct_Object_References',
    },
    fixable: 'code',
    hasSuggestions: true,
    schema: [
      {
        type: 'object',
        properties: {
          severity: {
            type: 'string',
            enum: ['warn', 'error'],
            default: 'warn',
          },
        },
        additionalProperties: false,
      },
    ],
    messages: {
      internalIdInUrl:
        'Potential IDOR violation: "{{property}}" (internal ID) used in URL context. Use ".extid" instead for enumeration resistance.',
      suggestExtId: 'Replace with ".extid"',
    },
  },

  create(context: Rule.RuleContext): Rule.RuleListener {
    return {
      /**
       * Check member expressions like `entity.id` in template literals or string concatenations
       */
      MemberExpression(node: MemberExpression & Rule.NodeParentExtension): void {
        // Only check identifier properties
        if (node.property.type !== 'Identifier') {
          return;
        }

        const propertyName = node.property.name.toLowerCase();

        // Skip if it's already using an external ID
        if (EXTERNAL_ID_PROPERTIES.includes(propertyName)) {
          return;
        }

        // Check if this is an internal ID property
        if (!INTERNAL_ID_PROPERTIES.includes(propertyName)) {
          return;
        }

        // Check if we're in a URL context
        if (!isInUrlContext(node, context)) {
          return;
        }

        // Report the issue
        context.report({
          node,
          messageId: 'internalIdInUrl',
          data: {
            property: node.property.name,
          },
          suggest: [
            {
              messageId: 'suggestExtId',
              fix(fixer): Rule.Fix {
                return fixer.replaceText(node.property, 'extid');
              },
            },
          ],
        });
      },

      /**
       * Check template literals for patterns like `/${entity}.id}`
       * This catches cases where the MemberExpression check might miss
       */
      TemplateLiteral(node: TemplateLiteral & Rule.NodeParentExtension): void {
        const sourceCode = context.sourceCode || context.getSourceCode();
        const source = sourceCode.getText(node);

        // Quick check - does this look like a URL?
        if (!URL_PATTERNS.some((pattern) => pattern.test(source))) {
          return;
        }

        // Check for any internal ID property in the template using single regex
        // Matches patterns like `.id}`, `.objid}`, `.owner_id}` etc.
        const internalIdPattern = new RegExp(
          `\\.\\s*(${INTERNAL_ID_PROPERTIES.join('|')})\\s*[}\`]`
        );
        const match = source.match(internalIdPattern);

        if (match) {
          // The MemberExpression handler should catch most cases,
          // but we report as a fallback
          context.report({
            node,
            messageId: 'internalIdInUrl',
            data: {
              property: match[1], // The captured property name
            },
          });
        }
      },
    };
  },
};

export default rule;
