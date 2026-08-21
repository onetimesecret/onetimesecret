// src/services/incomingConfig.service.ts

/**
 * Domain Incoming Configuration Service
 *
 * CRUD operations for the per-domain incoming-secrets recipients
 * configuration. Backed by the `Onetime::CustomDomain::IncomingConfig`
 * Familia model and the
 * `/api/domains/:extid/incoming-config` Logic endpoints.
 *
 * The admin endpoint returns plaintext `{email, name}` recipients so the
 * client can round-trip the full list on save (single source of truth).
 * Anonymous-sender flows hit a different endpoint that returns hashed
 * digests — that path is unaffected.
 */

import { createApi } from '@/api';
import type { PutDomainIncomingConfigRequest } from '@/schemas/api/domains/requests/incoming-config';
import {
  getDomainIncomingConfigResponseSchema,
  putDomainIncomingConfigResponseSchema,
} from '@/schemas/api/domains/responses/incoming-config';
import type { CustomDomainIncomingConfig } from '@/schemas/shapes/domains/incoming-config';
import { projectSchemaIssues } from '@/utils/telemetry/schemaIssueProjection';
import { gracefulParse, strictParse } from '@/utils/schemaValidation';

const $api = createApi();

/**
 * Wrapper for incoming-config responses.
 *
 * `record` is the parsed config. The GetIncomingConfig endpoint returns
 * an empty/unconfigured state (enabled=false, recipients=[]) when no
 * IncomingConfig record exists, so consumers do not need to handle a
 * 404-as-missing case the way SsoService does — only true domain-not-found
 * 404s reach the caller.
 */
export interface IncomingConfigResponse {
  record: CustomDomainIncomingConfig;
}

export const IncomingConfigService = {
  /**
   * Get the incoming configuration for a domain.
   *
   * Returns the empty/unconfigured state when no IncomingConfig record
   * exists (enabled=false, recipients=[]). A 404 means the domain itself
   * doesn't exist and is allowed to propagate.
   *
   * @param domainExtId - Domain external ID
   */
  async getConfigForDomain(domainExtId: string): Promise<IncomingConfigResponse> {
    const response = await $api.get(`/api/domains/${domainExtId}/incoming-config`);
    const result = gracefulParse(
      getDomainIncomingConfigResponseSchema,
      response.data,
      'GetDomainIncomingConfigResponse',
    );
    if (!result.ok) {
      // Log the PROJECTION, never the raw ZodError.
      //
      // `gracefulParse` returns the unprojected error by contract, and a Zod v4
      // issue carries `message`, `values`, `keys` and `params` — an audit found
      // a real `params: { leaked: 'sk_live_…' }`. Dumping `result.error` here
      // routed the payload straight around the projection chokepoint that every
      // other telemetry surface goes through. Production is mitigated (the
      // rolldown minifier's `dropConsole` strips our `console.*`, and
      // breadcrumbPolicy drops console `data.arguments`), so the live exposure
      // was a DEV session pointed at a real DSN — which is a normal way to work
      // here, not a hypothetical.
      //
      // `projectSchemaIssues` yields the same value-free rows the Sentry event
      // carries: field path, issue code, expected/received TYPE, issue count.
      // That is what a developer reads off the console anyway.
      // `ParseResult.error` is nullable (a non-Zod failure reports no error at
      // all), so the null case logs the bare fact and nothing derived.
      const projection = result.error
        ? projectSchemaIssues(result.error, response.data, 'GetDomainIncomingConfigResponse')
        : null;
      console.error(
        'Failed to parse incoming-config response:',
        projection ? `${projection.issueCount} issue(s)` : 'no issue detail available',
        projection?.rows ?? [],
      );
      throw new Error('Failed to parse incoming-config response from server');
    }
    return { record: result.data.record };
  },

  /**
   * Replace the incoming configuration for a domain.
   *
   * Carries the full intended state: enabled flag + complete recipients
   * list. The backend preserves existing recipients only when the
   * `recipients` key is omitted from the body; the frontend always
   * sends the full list, so this is a straight replacement.
   *
   * @param domainExtId - Domain external ID
   * @param payload - Full intended state (enabled + recipients)
   */
  async putConfigForDomain(
    domainExtId: string,
    payload: PutDomainIncomingConfigRequest,
  ): Promise<IncomingConfigResponse> {
    const response = await $api.put(`/api/domains/${domainExtId}/incoming-config`, payload);
    const validated = strictParse(putDomainIncomingConfigResponseSchema, response.data);
    return { record: validated.record };
  },

  /**
   * Delete the incoming configuration for a domain.
   *
   * Removes the IncomingConfig record entirely. The next GET will
   * return an empty/unconfigured state.
   *
   * @param domainExtId - Domain external ID
   */
  async deleteConfigForDomain(domainExtId: string): Promise<void> {
    await $api.delete(`/api/domains/${domainExtId}/incoming-config`);
  },
};
