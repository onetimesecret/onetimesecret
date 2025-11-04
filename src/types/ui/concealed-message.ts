// src/types/ui/concealed-message.ts

import { ConcealDataResponse } from '@/schemas/api';

export interface ConcealedMessage {
  id: string;
  metadata_identifier: string;
  secret_identifier: string;
  response: ConcealDataResponse;
  clientInfo: {
    hasPassphrase: boolean;
    ttl: number;
    createdAt: Date;
  };
}
