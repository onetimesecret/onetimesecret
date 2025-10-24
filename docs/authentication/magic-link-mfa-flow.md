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

## User Journey: MFA Recovery Flow

For users who are stuck in MFA verification and cannot complete authentication:

### The Problem

Users can become locked out of MFA verification in several scenarios:

1. **Lost/Broken Authenticator Device**: Phone lost, broken, or reset
2. **Invalidated OTP Keys**: Server-side MFA configuration changes (e.g., `otp_keys_use_hmac` toggled)
3. **No Recovery Codes**: User didn't save or lost their backup recovery codes
4. **App Reinstall**: Authenticator app reinstalled without backup

**Stuck State:**
- Session has `awaiting_mfa = true`
- User at `/mfa-verify` page
- OTP codes don't work (wrong secret)
- Recovery codes unavailable or invalid
- **No escape route** - infinite loop

### Recovery Solution

The MFA recovery flow provides a safe escape mechanism using email verification. The key architectural insight is that **email_auth (magic links) completes by triggering the standard login flow**, which allows the `after_login` hook to intercept and handle the recovery case before the normal MFA check occurs.

#### Flow Diagram

This diagram illustrates how the recovery flow integrates with the standard authentication pipeline:

```
User clicks magic link
         ↓
Email auth validates token
         ↓
Rodauth triggers LOGIN
         ↓
after_login hook fires
         ↓
Check: session[:mfa_recovery_mode]?
    ├── YES → Disable MFA → Continue login (skip MFA check)
    └── NO  → Check uses_two_factor_authentication?
                ├── YES → Set awaiting_mfa, defer session sync
                └── NO  → Complete session sync normally
```

**Key Points:**
- Email authentication doesn't bypass the login flow—it triggers it
- The `after_login` hook runs for ALL login methods (password, email_auth, etc.)
- Recovery check happens **before** the standard MFA check via `if/elsif` branching
- When recovery mode is detected, MFA is disabled and flow continues to normal authentication
- Without recovery mode, the standard MFA check applies as usual

### 1. Initiate Recovery
At `/mfa-verify` page:
- User clicks "Can't access your authenticator?"
- Recovery help section expands
- Explanation: "We can send a recovery link to disable 2FA"
- User clicks "Send recovery email"

### 2. Request Processing
Backend (`POST /auth/mfa-recovery-request`):
```ruby
# Validates user is in awaiting_mfa state
unless session[:awaiting_mfa]
  return { error: 'MFA recovery not applicable' }
end

# Set recovery mode flag
session[:mfa_recovery_mode] = true

# Send magic link via email_auth
_email_auth_key_insert(account_id)
send_email_auth_email
```

### 3. Email Sent
- User receives email with magic link
- Subject: "Login Link"
- Link format: `https://app.com/auth/email-login?key=TOKEN`
- Token expires in 15 minutes (standard email_auth expiration)

### 4. Click Recovery Link
User clicks link in email:
- Standard magic link flow processes token
- `after_email_auth` hook detects `session[:mfa_recovery_mode]`
- **MFA automatically disabled**:
  - OTP keys removed from `account_otp_keys` table
  - Recovery codes deleted from `account_recovery_codes` table
- Recovery mode flag cleared
- Completion flag set: `session[:mfa_recovery_completed] = true`

### 5. Authenticated with Warning
After successful email verification:
- User fully authenticated (MFA disabled)
- `session['awaiting_mfa'] = false`
- `session['authenticated'] = true`
- Redirected to dashboard

### 6. Post-Login Notification
Frontend router `afterEach` hook:
```typescript
if (window.__ONETIME_STATE__.mfa_recovery_completed) {
  notificationsStore.show(
    'Two-factor authentication has been disabled due to account recovery. ' +
    'Please re-enable it from your account settings.',
    'warning',
    'top'
  );
}
```

**User sees:**
- Warning notification banner at top
- Prompt to re-enable MFA in account settings
- Full access to account restored

### Security Implications

**Recovery Security Model:**
- Requires email access (same as password reset)
- Uses existing email_auth infrastructure (cryptographically secure tokens)
- Only works when user is partially authenticated (already passed first factor)
- Automatically disables MFA (prevents stuck state from recurring)

**Trust Model:**
- Email access = account ownership proof
- If email compromised, account already at risk
- Recovery doesn't weaken security vs password reset
- User must re-enable MFA manually (conscious security decision)

**Attack Scenarios:**

1. **Attacker with email access but no MFA device**
   - Can use recovery to disable MFA and gain access
   - ⚠️ Same risk as password reset flow
   - ✓ Mitigation: Email security is primary defense

2. **Legitimate user locked out**
   - Recovery provides escape without admin intervention
   - ✓ Better UX than manual admin reset
   - ✓ Encourages MFA re-enablement after recovery

**Best Practices:**
- Log all recovery attempts (implemented via SemanticLogger)
- Monitor recovery frequency (multiple recoveries = suspicious)
- Send notification email when MFA disabled
- Prompt user to re-enable MFA on next login

### Technical Implementation

**Backend Hook (Passwordless):**
```ruby
# apps/web/auth/config/hooks/passwordless.rb
auth.after_email_auth do
  if session[:mfa_recovery_mode]
    # Disable OTP authentication
    _otp_remove_auth_failures
    _otp_remove_key(account_id)

    # Remove recovery codes
    db[recovery_codes_table]
      .where(recovery_codes_id_column => account_id)
      .delete

    # Set completion flag for frontend notification
    session[:mfa_recovery_completed] = true
    session.delete(:mfa_recovery_mode)
  end
end
```

**Backend Route (MFA):**
```ruby
# apps/web/auth/config/hooks/mfa.rb
auth.route('mfa-recovery-request') do |r|
  r.post do
    # Validate awaiting_mfa state
    # Set recovery mode flag
    # Send email_auth magic link
    # Return success response
  end
end
```

**Frontend Composable:**
```typescript
// src/composables/useMfa.ts
async function requestMfaRecovery(): Promise<boolean> {
  const response = await $api.post('/auth/mfa-recovery-request', {});

  if ('error' in response.data) {
    error.value = response.data.error;
    return false;
  }

  notificationsStore.show('Recovery email sent', 'success', 'top');
  return true;
}
```

**Frontend Component:**
```vue
<!-- src/views/auth/MfaVerify.vue -->
<div v-if="showRecoveryHelp">
  <h3>Lost access to your authenticator?</h3>
  <p>We can send a recovery link to disable 2FA</p>
  <button @click="handleMfaRecovery">
    Send recovery email
  </button>
</div>
```

### Configuration

**Requirements:**
```bash
# Must have email_auth enabled
export ENABLE_MAGIC_LINKS=true

# MFA must be enabled
export ENABLE_MFA=true

# Email delivery configured
# (Mailpit for dev, production SMTP for prod)
```

**Optional Settings:**
```ruby
# apps/web/auth/config/features/passwordless.rb
auth.email_auth_deadline_interval 15.minutes  # Recovery link TTL
auth.email_auth_skip_resend_email_within 30.seconds  # Rate limit
```

### Testing MFA Recovery

**Setup Test Scenario:**
```bash
# 1. Create user with MFA enabled
bin/ots console
cust = Onetime::Customer.load('testuser@example.com')
# Enable MFA through UI or API

# 2. Invalidate MFA (simulate config change)
# Toggle otp_keys_use_hmac in config
# Or manually update account_otp_keys table

# 3. Verify stuck state
# Login with email/password
# Should redirect to /mfa-verify
# OTP codes won't work
```

**Test Recovery Flow:**
```bash
# 1. Click "Can't access authenticator?"
# 2. Click "Send recovery email"
# 3. Check mailpit at http://localhost:1025
# 4. Click magic link in email
# 5. Verify:
#    - User logged in successfully
#    - Warning notification shown
#    - MFA disabled in database
#    - Can re-enable MFA from settings
```

**Database Verification:**
```ruby
# Before recovery
db[:account_otp_keys].where(account_id: user.id).count  # => 1
db[:account_recovery_codes].where(account_id: user.id).count  # => 16

# After recovery
db[:account_otp_keys].where(account_id: user.id).count  # => 0
db[:account_recovery_codes].where(account_id: user.id).count  # => 0
```

**Expected Logs:**
```
[Auth] User logged in: test@example.com
[Auth] MFA required for test@example.com, deferring session sync
[Auth] MFA recovery requested, account_id: 123
[Auth] MFA recovery email sent
[Auth] MFA recovery initiated via email auth
[Auth] MFA disabled via recovery flow
```

### UI States

**MFA Verify Page - Default:**
```
┌─────────────────────────────────────┐
│  Two-Factor Authentication          │
│                                      │
│  Enter authentication code           │
│                                      │
│  [_] [_] [_] [_] [_] [_]            │
│                                      │
│  Use a recovery code instead         │
│             or                       │
│  Can't access your authenticator?   │
└─────────────────────────────────────┘
```

**Recovery Help - Expanded:**
```
┌─────────────────────────────────────┐
│  Lost access to your authenticator? │
│                                      │
│  We can send a recovery link to     │
│  your email. This will disable      │
│  two-factor authentication.         │
│                                      │
│  [Send recovery email]               │
│  [Cancel]                            │
└─────────────────────────────────────┘
```

**Recovery Email Sent:**
```
┌─────────────────────────────────────┐
│  ✓ Check your email                 │
│                                      │
│  We've sent a recovery link to      │
│  your email address. Click the      │
│  link to complete your login and    │
│  disable MFA.                        │
└─────────────────────────────────────┘
```

### Troubleshooting

**Recovery button not visible**
- Ensure `ENABLE_MAGIC_LINKS=true`
- Check `awaiting_mfa` state in session
- Verify UI i18n strings loaded

**Recovery email not sending**
- Check email service configuration
- Verify `email_auth` feature enabled
- Check Mailpit/SMTP logs

**MFA not disabled after recovery**
- Check `after_email_auth` hook execution
- Verify `session[:mfa_recovery_mode]` flag set
- Check database for OTP key removal

**Notification not showing**
- Verify `mfa_recovery_completed` in window state
- Check router `afterEach` hook execution
- Ensure notifications store initialized

### Related Files

**Backend:**
- `apps/web/auth/config/hooks/passwordless.rb` - Recovery email auth hook
- `apps/web/auth/config/hooks/mfa.rb` - Recovery request route
- `apps/web/auth/config/hooks/login.rb` - Clear completion flag

**Frontend:**
- `src/composables/useMfa.ts` - Recovery request method
- `src/views/auth/MfaVerify.vue` - Recovery UI
- `src/router/guards.routes.ts` - Notification display
- `src/locales/en.json` - Recovery UI strings

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
- **Push Notifications**: Mobile app push for MFA approval
- **Risk-Based MFA**: Require MFA only for suspicious locations/IPs
- **Recovery Monitoring**: Alert on multiple recovery attempts (potential account compromise)
- **Recovery Notifications**: Send email when MFA disabled via recovery (security audit trail)
