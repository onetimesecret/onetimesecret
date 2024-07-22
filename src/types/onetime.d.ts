
// Define the cust object
export interface Cust {
  custid: string;
  role: string;
  planid: string;
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
