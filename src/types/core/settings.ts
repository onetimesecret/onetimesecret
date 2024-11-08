
export interface SecretOptions {
  // Default Time-To-Live (TTL) for secrets in seconds
  default_ttl: number; // Default: 604800 (7 days in seconds)

  // Available TTL options for secret creation (in seconds)
  // These options will be presented to users when they create a new secret
  // Format: Array of integers representing seconds
  ttl_options: number[]; // Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
}

export interface AuthenticationSettings {
  enabled: boolean;
  signup: boolean;
  signin: boolean;
  autoverify: boolean;
}
