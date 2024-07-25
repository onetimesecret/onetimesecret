/* eslint-disable no-unused-vars */

// Define the cust object
export interface Cust {
  custid: string;
  role: string;
  planid?: string;
  plan: Plan;
  verified: string;
  updated: string;
  created: string;
  secrets_created: string;
  active: string;
}

// Define the plan object
export interface Plan {
  planid: string;
  price: number;
  discount: number;
  options: {
    ttl: number;
    size: number;
    api: boolean;
    cname?: boolean;
    private?: boolean;
    name: string;
  };
}

export type FormSubmissionOptions = {
  url: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;
  getFormData?: () => FormData | URLSearchParams;
  onSuccess?: (data: Record<string, string>) => void | Promise<void>;
  onError?: (data: Record<string, string>) => void | Promise<void>;
  handleShrimp?: (shrimp: string) => void | Promise<void>
};
