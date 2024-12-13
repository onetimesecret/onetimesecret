// src/router/resolvers/secretResolver.ts

import { useSecretsStore } from '@/stores/secretsStore';
import type { AsyncDataResult, SecretRecordApiResponse } from '@/types/api/responses';
import type { NavigationGuardNext, RouteLocationNormalized } from 'vue-router';

/**
 * Route resolver for secret pages
 * Preloads secret data and handles branded/canonical views
 *
 * @example
 * ```ts
 * // In route config:
 * {
 *   path: '/secret/:secretKey',
 *   component: ShowSecretContainer,
 *   beforeEnter: resolveSecret,
 *   meta: {
 *     domain_strategy: 'canonical'|'branded'
 *   }
 * }
 * ```
 *
 * Regarding performance:
 *  1. The Zod validation happens once after the API call
 *  2. The `AsyncDataResult` structure is just object assignment - no validation
 *  3. The real performance cost would be in the Zod validation, but it's:
 *     - Only on initial load
 *     - Prevents invalid data from reaching components
 *     - Helps catch API changes early
 *
 *  We could potentially optimize by:
 *  1. Moving validation to development only
 *  2. Caching validation results
 *  3. Using lighter validation in production
 *
 */
export async function resolveSecret(
  to: RouteLocationNormalized,
  _from: RouteLocationNormalized,
  next: NavigationGuardNext
) {
  const secretKey = to.params.secretKey as string
  const store = useSecretsStore()

  try {
    const result = await store.loadSecret(secretKey)

    // Structure matches existing component expectations
    const initialData: AsyncDataResult<SecretRecordApiResponse> = {
      status: 200,
      data: {
        record: result.record,
        details: result.details
      },
      error: null
    }

    // Make data available to components via route meta
    to.meta.initialData = initialData

    next()
  } catch (error) {
    console.error('Failed to load secret:', error)

    // Maintain same shape even for errors
    const initialData: AsyncDataResult<SecretRecordApiResponse> = {
      status: error instanceof Error ? 500 : 404,
      data: null,
      error: error instanceof Error ? error.message : 'Failed to load secret'
    }

    to.meta.initialData = initialData
    next() // Still proceed to route to show error state
  }
}
