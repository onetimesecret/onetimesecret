type JSONValue = string | number | boolean | { [key: string]: JSONValue } | JSONValue[];

// locales.d.ts
declare module '@/locales/*.json' {
  interface Common {
    button_generate_secret_short: string;
    generate_password_disabled: string;
    email_placeholder: string;
    password_placeholder: string;
    // Add other common keys as needed
    [key: string]: JSONValue; // Allow additional keys
  }

  interface Web {
    COMMON: Common;
    // Add other sections as needed
    [key: string]: JSONValue; // Allow additional keys
  }

  const value: {
    web: Web;
    // Add other top-level sections as needed
    [key: string]: JSONValue; // Allow additional keys
  };

  export default value;
}
