# Magic Link + MFA Authentication Flow

## Overview

This document describes the complete authentication flow when a user with Multi-Factor Authentication (MFA) enabled uses magic link (passwordless) login. This provides defense-in-depth security by combining email verification with device-based authentication.

## Authentication States

The system recognizes three distinct authentication states:

1. **Anonymous**: No authentication attempt
   - `authenticated = false`
   - `awaiting_mfa = false`
   - User sees: Sign In / Sign Up links

2. **Partially Authenticated**: First factor complete, awaiting MFA
   - `authenticated = false`
   - `awaiting_mfa = true`
   - User sees: User menu with amber badge, "Complete MFA" prompt

3. **Fully Authenticated**: All factors complete
   - `authenticated = true`
   - `awaiting_mfa = false`
   - User sees: Normal user menu, full access

## User Journey: Magic Link Without MFA

For users who have NOT enabled MFA:

### 1. Request Magic Link
- User enters email address at `/signin`
- Clicks "Send Magic Link"
- System generates secure token
- Email sent with time-limited link (15 min default)

### 2. Receive Email
- Email contains login link: `https://app.com/auth/email-login?key=TOKEN`
- Token is cryptographically secure, single-use

### 3. Click Magic Link
- Browser opens link
- `before_email_auth_route` hook validates token presence
- Rodauth verifies token validity and expiration
- Token consumed (marked as used)

### 4. Authenticated
- `session['authenticated_by'] = ['email_auth']`
- `session['authenticated'] = true`
- `session['awaiting_mfa'] = false` (no MFA configured)
- User redirected to dashboard
- **Full access granted**

## User Journey: Magic Link With MFA

For users who HAVE enabled MFA (TOTP or WebAuthn):

### 1-3. Same as Above
Email request, receipt, and link click identical to non-MFA flow.

### 4. First Factor Complete
After successful email verification:
- `session['authenticated_by'] = ['email_auth']`
- `after_login` hook detects MFA is configured
- `session['awaiting_mfa'] = true`
- User redirected to `/auth/mfa-verify`

**At this point:**
- Email ownership proven ✓
- Device possession NOT yet proven ✗
- User partially authenticated

### 5. Frontend State
- `awaiting_mfa = true` sent to frontend via `/window`
- User menu appears with amber badge indicator
- Menu shows: "MFA verification required"
- Prominent "Complete MFA Verification" link

### 6. Complete MFA
User completes second factor:

**Option A: TOTP (Time-based One-Time Password)**
- User opens authenticator app (Google Authenticator, Authy, etc.)
- Enters 6-digit code
- POST `/auth/otp-auth` with code
- Rodauth verifies code against stored secret

**Option B: WebAuthn (Hardware Key/Biometric)**
- User inserts security key or uses biometric
- Browser WebAuthn API handles challenge/response
- POST `/auth/webauthn-auth` with credential
- Rodauth verifies credential signature

### 7. Fully Authenticated
After successful MFA:
- `session['awaiting_mfa'] = false`
- `session['authenticated'] = true`
- `after_otp_auth` or `after_webauthn_auth` hook fires
- User redirected to dashboard
- **Full access granted**

## Security Rationale

### Why Require MFA After Magic Link?

Magic links prove email ownership but don't protect against:
- **Compromised email accounts**: Attacker with email access can click link
- **Email forwarding rules**: Malicious forwarding could intercept links
- **Shared email access**: Multiple people with access to same inbox

By requiring MFA after magic link:
1. **Email verification** = "Something you have" (email access)
2. **MFA verification** = "Something you know/have" (TOTP secret or security key)

This provides **defense in depth** - both factors must be compromised for account access.

### Token Security

Magic link tokens are:
- **Cryptographically random**: High entropy, unpredictable
- **Single-use**: Token invalidated after one successful use
- **Time-limited**: Default 15 minute expiration
- **HTTPS-only**: Protected in transit (configured requirement)

## Technical Implementation

### Backend (Ruby/Rodauth)

**Session Keys:**
```ruby
session['authenticated_by']  # ['email_auth'] or ['password']
session['awaiting_mfa']      # true/false
session['authenticated']     # true/false (only true after all factors)
```

**Hook Flow:**
```ruby
# apps/web/auth/config/hooks/login.rb
auth.after_login do
  # Use Rodauth's built-in two_factor_base method
  # Returns true if: logged_in? && !two_factor_authenticated? && uses_two_factor_authentication?
  if two_factor_partially_authenticated?
    session[:awaiting_mfa] = true
    # Defer session sync until MFA complete
  else
    session[:awaiting_mfa] = false
    # Sync session immediately (no MFA required)
  end
end

# apps/web/auth/config/rodauth_overrides.rb
def require_authentication
  if session[:awaiting_mfa]
    redirect otp_auth_route  # Block access until MFA complete
  end
  super
end
```

### Frontend (Vue 3/TypeScript)

**Window State:**
```typescript
interface WindowState {
  authenticated: boolean;    // Full authentication complete
  awaiting_mfa: boolean;     // First factor done, need MFA
  cust: Customer | null;     // User data (present in both states)
}
```

**User Menu Logic:**
```vue
<!-- Show menu if authenticated OR awaiting MFA -->
<template v-if="authenticated || awaiting_mfa">
  <UserMenu
    :cust="cust"
    :awaiting-mfa="awaiting_mfa" />
</template>
```

**Visual Indicators:**
```vue
<!-- Amber badge when MFA pending -->
<div :class="awaitingMfa ? 'bg-amber-500' : 'bg-brand-500'">
  {{ userInitials }}
</div>

<!-- MFA required notice in menu -->
<div v-if="awaitingMfa" class="bg-amber-50">
  MFA verification required
</div>
```

## Configuration

### Enable Passwordless Authentication

```ruby
# apps/web/auth/config/features/passwordless.rb
auth.enable :email_auth
auth.email_auth_deadline_interval 15.minutes  # Link expiration
```

### Enable MFA

```ruby
# apps/web/auth/config/features/security.rb
auth.enable :otp          # TOTP
auth.enable :webauthn     # Hardware keys/biometrics
```

### HMAC Secret (Required)

```bash
# Environment variable (production)
export HMAC_SECRET="your-secure-random-secret-min-32-chars"

# Or fallback (development only)
export AUTH_SECRET="dev-secret"
```

## Related Files

**Backend Configuration:**
- `apps/web/auth/config/hooks/passwordless.rb` - Magic link hooks
- `apps/web/auth/config/hooks/login.rb` - MFA detection
- `apps/web/auth/config/rodauth_overrides.rb` - Authentication guards
- `apps/web/auth/config/features/passwordless.rb` - Email auth config
- `apps/web/auth/config/features/security.rb` - MFA config

**Backend Serialization:**
- `apps/web/core/views/helpers/initialize_view_vars.rb` - Session state extraction
- `apps/web/core/views/serializers/authentication_serializer.rb` - Frontend state

**Frontend Components:**
- `src/components/layout/MastHead.vue` - Header with user menu
- `src/components/navigation/UserMenu.vue` - User dropdown menu
- `src/services/window.service.ts` - Window state access

## Testing

### Manual Test Flow

1. **Create test user with MFA:**
   ```bash
   bin/ots console
   # Enable MFA for test user
   ```

2. **Request magic link:**
   ```bash
   curl -X POST http://localhost:7143/auth/email-login-request \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com"}'
   ```

3. **Check email logs for link**

4. **Click link, verify redirect to MFA page**

5. **Complete MFA, verify full authentication**

### Expected Session States

**After magic link click:**
```ruby
session['authenticated_by']  # => ['email_auth']
session['awaiting_mfa']      # => true
session['authenticated']     # => false (blocked by awaiting_mfa)
```

**After MFA completion:**
```ruby
session['authenticated_by']  # => ['email_auth']
session['awaiting_mfa']      # => false
session['authenticated']     # => true
```

## Troubleshooting

### User menu doesn't appear after magic link

**Check:**
1. Is `awaiting_mfa` being sent to frontend?
   - Look for `awaiting_mfa: true` in `/window` response
2. Is `isUserPresent` computed correctly?
   - Should be true if `authenticated || awaiting_mfa`
3. Is MFA actually configured for test user?
   - Check `account_otp_keys` table

### HMAC secret error on magic link click

**Error:** `Rodauth::ConfigurationError: hmac_secret not set`

**Fix:** Ensure `HMAC_SECRET` environment variable is set and `hmac_secret_value` method returns value (not just assigns it)

### MFA bypass when it should be required

**Check:**
1. `after_login` hook is setting `awaiting_mfa`
2. `require_authentication` override is checking `session[:awaiting_mfa]`
3. User actually has MFA configured in database

## Future Enhancements

- **Remember Device**: Skip MFA for trusted devices (30 days)
- **Backup Codes**: Recovery codes if MFA device lost
- **Push Notifications**: Mobile app push for MFA approval
- **Risk-Based MFA**: Require MFA only for suspicious locations/IPs
