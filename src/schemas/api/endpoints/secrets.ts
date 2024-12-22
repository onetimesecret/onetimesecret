// schemas/api/endpoints/secrets.ts
import { metadataSchema, secretSchema } from '@/schemas/models';

export const concealEndpointSchema = registry.register(
  'SecretConceal',
  secretSchema.merge(metadataSchema).extend({
    // Endpoint-specific fields
    recipientEmail: z.string().email().optional(),
    ttl: z.number()
  })
);

registry.registerPath({
  method: 'post',
  path: '/conceal',
  request: { body: { content: { 'application/json': { schema: concealEndpointSchema } } } },
  responses: {
    200: { content: { 'application/json': { schema: createRecordResponseSchema(secretSchema) } } }
  }
});
