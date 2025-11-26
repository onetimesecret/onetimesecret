// src/scripts/openapi/route-config.ts

/**
 * Data-Driven Route Configuration for OpenAPI Generation
 *
 * This module provides a declarative approach to mapping routes to OpenAPI paths,
 * replacing the manual if/else pattern with a configuration-driven system.
 */

import type { ZodTypeAny } from 'zod';
import type { RouteConfig as OpenAPIRouteConfig } from '@asteasolutions/zod-to-openapi';
import type { OttoRoute } from './otto-routes-parser';

/**
 * Route mapping configuration
 */
export interface RouteMapping {
  /** Route pattern matcher (method + path) */
  matcher: {
    method: string;
    path: string | RegExp;
  };

  /** OpenAPI path configuration */
  openapi: {
    summary: string;
    description: string;
    tags?: string[];
    requestSchema?: ZodTypeAny;
    responseSchema?: ZodTypeAny;
    responses?: OpenAPIRouteConfig['responses'];
  };
}

/**
 * Matches a route against a pattern
 */
export function matchesRoute(route: OttoRoute, matcher: RouteMapping['matcher']): boolean {
  if (route.method !== matcher.method) {
    return false;
  }

  if (typeof matcher.path === 'string') {
    return route.path === matcher.path;
  }

  return matcher.path.test(route.path);
}

/**
 * Finds the matching route configuration
 */
export function findRouteMapping(
  route: OttoRoute,
  mappings: RouteMapping[]
): RouteMapping | undefined {
  return mappings.find(mapping => matchesRoute(route, mapping.matcher));
}

/**
 * Standardized error responses for reuse across all APIs
 */
export const standardErrorResponses = {
  400: {
    description: 'Bad Request - Invalid request parameters or body'
  },
  401: {
    description: 'Unauthorized - Authentication required'
  },
  403: {
    description: 'Forbidden - Insufficient permissions'
  },
  404: {
    description: 'Not Found - Resource does not exist'
  },
  429: {
    description: 'Too Many Requests - Rate limit exceeded'
  },
  500: {
    description: 'Internal Server Error - Something went wrong'
  }
};

/**
 * Helper to merge custom responses with standard errors
 */
export function mergeResponses(
  customResponses: OpenAPIRouteConfig['responses'],
  includeErrors: (keyof typeof standardErrorResponses)[] = [400, 401, 500]
): OpenAPIRouteConfig['responses'] {
  const errorResponses = Object.fromEntries(
    includeErrors.map(code => [code, standardErrorResponses[code]])
  );

  return {
    ...errorResponses,
    ...customResponses
  };
}
