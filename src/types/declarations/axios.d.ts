// src/types/declarations/axios.d.ts

import 'axios';

declare module 'axios' {
  interface AxiosRequestConfig {
    /**
     * Declares that no person caused this request: a timer or a
     * tab-visibility refresh, not navigation or a click. The request
     * interceptor (src/plugins/axios/interceptors.ts) turns it into
     * `X-Session-Activity: passive`, and the server then verifies the session
     * in full but does not count the request as activity, so an unattended
     * tab still reaches its inactivity deadline.
     *
     * Per request only. Never set it as an instance default: every GET would
     * become passive and people actively using the app would be signed out.
     * Honoured on GET and HEAD only, by the interceptor and by the server.
     */
    passive?: boolean;
  }
}
