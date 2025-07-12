// src/types/ui/concealed-message.ts

import { ConcealDataResponse } from '@/schemas/api';

export interface ConcealedMessage {
  id: string;
  metadata_key: string;
  secret_key: string;
  response: ConcealDataResponse;
  clientInfo: {
    hasPassphrase: boolean;
    ttl: number;
    createdAt: Date;
  };
}
