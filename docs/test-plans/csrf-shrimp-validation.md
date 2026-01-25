# CSRF Shrimp Validation Test Plan

## Background

Onetime Secret uses "shrimp" as the CSRF parameter name instead of the standard "authenticity_token". This naming is a legacy convention but requires careful alignment between frontend and backend to ensure CSRF protection works correctly.

### Parameter Alignment

The `Rack::Protection::AuthenticityToken` middleware is configured with:

```ruby
# lib/onetime/middleware/security.rb
'AuthenticityToken' => {
  key: :authenticity_token,
  klass: Rack::Protection::AuthenticityToken,
  options: {
    authenticity_param: 'shrimp',  # <-- Must match frontend
    # ...
  },
}
```

The frontend components must use `name='shrimp'` in form submissions, not `name='authenticity_token'`.

### Token Flow

```
Backend session[:csrf]
    -> Serialized to window.__BOOTSTRAP_STATE__.shrimp
    -> bootstrapStore.shrimp
    -> csrfStore.shrimp
    -> Form hidden input (name="shrimp")
    -> Rack::Protection::AuthenticityToken validates
```

## Test Coverage Matrix

### Backend Tests

| Test File | Coverage | Status |
|-----------|----------|--------|
| `lib/onetime/middleware/security.rb` | CSRF middleware configuration with `authenticity_param: 'shrimp'` | Configuration |
| `spec/integration/simple/rhales_migration_spec.rb:253` | Verifies CSRF delivered via shrimp in serialized state | Integration |
| `try/support/test_helpers.rb:284` | Test helper for mock shrimp tokens | Test Support |

### Frontend Unit Tests

| Test File | Coverage | Status |
|-----------|----------|--------|
| `src/tests/stores/csrfStore.spec.ts` | Token initialization, updates, validation, periodic checks | Unit |
| `src/tests/apps/session/components/SsoButton.spec.ts` | Form creation with shrimp input, submission flow | Unit |
| `src/tests/apps/session/components/AuthMethodSelector.spec.ts` | SSO button conditional rendering | Unit |
| `src/tests/utils/features.spec.ts` | Feature flag detection including OmniAuth | Unit |

### E2E Tests

| Test File | Coverage | Status |
|-----------|----------|--------|
| `e2e/auth/sso-csrf.spec.ts` | SSO button CSRF flow, form verification, parameter naming | E2E |

## Detailed Test Cases

### 1. Backend: CSRF Configuration (lib/onetime/middleware/security.rb)

**What to verify:**
- `authenticity_param` is set to `'shrimp'`
- Middleware is enabled when `site.middleware.authenticity_token` is true
- API endpoints are excluded via `allow_if` callback

**Covered by:** Configuration file inspection, integration tests

### 2. Backend: Token Serialization (spec/integration/simple/rhales_migration_spec.rb)

**Test case at line 253:**
```ruby
it 'delivers CSRF via shrimp in serialized state (not meta tag)' do
  # CSRF is delivered via window.__BOOTSTRAP_STATE__.shrimp and X-CSRF-Token header
  expect(state_data).to have_key('shrimp')
end
```

### 3. Frontend: csrfStore Initialization (src/tests/stores/csrfStore.spec.ts)

**Key test cases:**
- Initializes with bootstrap.shrimp when available
- Loads shrimp from bootstrap for use in form CSRF protection
- Preserves bootstrap.shrimp through store reset
- Handles falsy but valid bootstrap.shrimp values
- Updates shrimp without affecting validity
- Validates shrimp through API call

### 4. Frontend: SsoButton Form Submission (src/tests/apps/session/components/SsoButton.spec.ts)

**Key test cases:**
- Creates form with POST method on click
- Form targets /auth/sso/oidc endpoint
- Includes CSRF token in form submission (input name="shrimp")
- Submits the form after creating it
- Shows loading state after button click

### 5. E2E: SSO CSRF Flow (e2e/auth/sso-csrf.spec.ts)

**Test cases:**
- SSO button is visible when OmniAuth is enabled
- SSO form submission includes shrimp CSRF token
- Shrimp token originates from bootstrap state
- SSO button shows loading state when clicked
- Form action points to correct OmniAuth endpoint (/auth/sso/oidc)
- Shrimp parameter uses correct field name (not authenticity_token)

## Manual Testing Steps

### Prerequisites
1. OmniAuth/OIDC configured with valid provider credentials
2. Environment variables set: `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_REDIRECT_URI`
3. `features.omniauth` enabled in bootstrap state

### Test Procedure

1. **Navigate to signin page**
   ```
   https://your-app.dev/signin
   ```

2. **Verify SSO button presence**
   - SSO button should appear below the divider "or continue with"
   - Button text: "Sign in with SSO"

3. **Inspect bootstrap state (DevTools Console)**
   ```javascript
   // Before app consumes it
   window.__BOOTSTRAP_STATE__.shrimp
   // Should return a non-empty string token
   ```

4. **Test form submission (DevTools Console)**
   ```javascript
   // Override form.submit to inspect
   HTMLFormElement.prototype.submit = function() {
     console.log('Form action:', this.action);
     console.log('Form method:', this.method);
     const shrimp = this.querySelector('input[name="shrimp"]');
     console.log('Shrimp value:', shrimp?.value);
   };
   ```

5. **Click SSO button and verify:**
   - Form action ends with `/auth/sso/oidc`
   - Form method is `POST`
   - Hidden input `shrimp` has non-empty value matching bootstrap shrimp

6. **Verify backend accepts token (Network tab)**
   - If IdP is configured, should redirect to IdP login
   - If CSRF fails, will return 403 or redirect with error

### Negative Test: Wrong Parameter Name

If frontend incorrectly uses `authenticity_token` instead of `shrimp`:

1. Modify SsoButton temporarily to use wrong name
2. Submit form
3. Expect: 403 Forbidden or CSRF error message
4. This confirms backend only accepts `shrimp` parameter

## Configuration Requirements

### Backend (lib/onetime/middleware/security.rb)

```ruby
'AuthenticityToken' => {
  key: :authenticity_token,
  klass: Rack::Protection::AuthenticityToken,
  options: {
    authenticity_param: 'shrimp',  # REQUIRED: Must be 'shrimp'
    allow_if: ->(env) {
      req = Rack::Request.new(env)
      req.path.start_with?('/api/') ||
        req.media_type == 'application/json' ||
        req.get_header('HTTP_ACCEPT')&.include?('application/json')
    },
  },
},
```

### Frontend (src/apps/session/components/SsoButton.vue)

```typescript
const csrfInput = document.createElement('input');
csrfInput.type = 'hidden';
csrfInput.name = 'shrimp';  // REQUIRED: Must match backend config
csrfInput.value = csrfStore.shrimp;
form.appendChild(csrfInput);
```

### Site Configuration (config/config.yaml)

```yaml
site:
  middleware:
    authenticity_token: true  # Enables CSRF protection
```

## Troubleshooting

### SSO button not appearing
- Verify `window.__BOOTSTRAP_STATE__.features.omniauth === true`
- Check OIDC environment variables are set
- Review server logs for OmniAuth configuration errors

### CSRF validation failing (403)
- Verify `authenticity_param: 'shrimp'` in security.rb
- Verify frontend uses `name='shrimp'` (not `authenticity_token`)
- Check session cookie is being sent
- Verify shrimp value in form matches session[:csrf]

### Token mismatch
- Clear browser cookies and reload
- Check for multiple session cookies (cookie tossing protection)
- Verify session store is consistent (Redis connection)

## Related Documentation

- [OmniAuth SSO Documentation](../authentication/omniauth-sso.md)
- [Rack::Protection Documentation](https://github.com/sinatra/sinatra/tree/main/rack-protection)
- [CSRF Protection Overview](https://owasp.org/www-community/attacks/csrf)
