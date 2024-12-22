// schemas/api/endpoints/secrets.ts
import { metadataSchema, secretSchema } from '@/schemas/models';
import { z } from 'zod';


/**
 * Schema for combined secret and metadata (conceal data)
 */
export const concealDataSchema = z.object({
  metadata: metadataSchema,
  secret: secretSchema,
  share_domain: z.string(),
});

export type ConcealData = z.infer<typeof concealDataSchema>;


/**
 *
 *  export const concealEndpointSchema = registry.register(
 *    'SecretConceal',
 *    secretSchema.merge(metadataSchema).extend({
 *      // Endpoint-specific fields
 *      recipientEmail: z.string().email().optional(),
 *      ttl: z.number()
 *    })
 *  );
 *
 *  registry.registerPath({
 *    method: 'post',
 *    path: '/conceal',
 *    request: { body: { content: { 'application/json': { schema: concealEndpointSchema } } } },
 *    responses: {
 *      200: { content: { 'application/json': { schema: createApiResponseSchema(secretSchema) } } }
 *    }
 *  });
 */
