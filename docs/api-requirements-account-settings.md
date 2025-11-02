# Account Settings API Requirements

This document outlines the API endpoints and data structures required by the frontend Account Settings pages.

## Overview

The Account Settings UI makes several assumptions about backend API endpoints that need to be implemented or verified. This document itemizes each requirement for the backend development team.

## Required Endpoints

### 1. Account Information Endpoint

**Current Status**: Loading state shows but data not populating
**Expected Endpoint**: `GET /api/v2/account/info`

**Response Schema**:
```json
{
  "email": "user@example.com",
  "email_verified": true,
  "created_at": "2024-01-15T10:30:00Z",
  "mfa_enabled": false,
  "recovery_codes_count": 0,
  "active_sessions_count": 1
}
```

**Used By**:
- `/account` (AccountIndex.vue)
- `/account/settings/profile` (ProfileSettings.vue)
- `/account/settings/security` (SecurityOverview.vue)

**Frontend Implementation**:
- Composable: `src/composables/useAccount.ts`
- Method: `fetchAccountInfo()`

---

### 2. Active Sessions Endpoint

**Current Status**: Shows "Endpoint not found"
**Expected Endpoint**: `GET /api/v2/account/sessions`

**Response Schema**:
```json
{
  "sessions": [
    {
      "id": "session_abc123",
      "device": "Chrome on macOS",
      "ip_address": "192.168.1.1",
      "location": "San Francisco, CA",
      "last_active": "2024-03-20T15:30:00Z",
      "created_at": "2024-03-15T10:00:00Z",
      "is_current": true
    }
  ],
  "total_count": 1
}
```

**Used By**:
- `/account/settings/security` (SecurityOverview.vue) - displays count
- `/account/settings/security/sessions` (ActiveSessions.vue) - full list

**Required Actions**:
- List all active sessions
- Revoke individual session: `DELETE /api/v2/account/sessions/:id`
- Revoke all other sessions: `DELETE /api/v2/account/sessions/others`

---

### 3. MFA Status & Management

**Current Status**: Partial - needs full CRUD operations
**Expected Endpoints**:

#### Get MFA Status
`GET /api/v2/account/mfa/status`

```json
{
  "enabled": false,
  "methods": []
}
```

#### Enable MFA
`POST /api/v2/account/mfa/enable`

**Request**:
```json
{
  "method": "totp",
  "verification_code": "123456"
}
```

**Response**:
```json
{
  "success": true,
  "backup_codes": ["code1", "code2", "..."],
  "qr_code": "data:image/png;base64,..."
}
```

#### Disable MFA
`DELETE /api/v2/account/mfa`

**Request**:
```json
{
  "verification_code": "123456",
  "password": "current_password"
}
```

**Used By**:
- `/account/settings/security` (SecurityOverview.vue) - displays status
- `/account/settings/security/mfa` (MfaSettings.vue) - full management

---

### 4. Recovery Codes

**Expected Endpoints**:

#### Get Recovery Codes Count
`GET /api/v2/account/recovery-codes/count`

```json
{
  "count": 8,
  "total": 10
}
```

#### Generate New Recovery Codes
`POST /api/v2/account/recovery-codes/generate`

**Request**:
```json
{
  "password": "current_password"
}
```

**Response**:
```json
{
  "codes": ["code1", "code2", "...", "code10"],
  "generated_at": "2024-03-20T15:30:00Z"
}
```

**Used By**:
- `/account/settings/security` (SecurityOverview.vue) - displays count
- `/account/settings/security/recovery-codes` (RecoveryCodes.vue) - full management

---

### 5. Password Change

**Current Status**: Needs validation
**Expected Endpoint**: `POST /api/v2/account/password`

**Request**:
```json
{
  "current_password": "old_password",
  "new_password": "new_password",
  "confirm_password": "new_password"
}
```

**Response**:
```json
{
  "success": "Password updated successfully"
}
```

**Error Response**:
```json
{
  "error": "Current password is incorrect",
  "field-error": ["current_password", "invalid"]
}
```

**Used By**:
- `/account/settings/security/password` (ChangePassword.vue)

---

### 6. API Key Management

**Current Status**: Partially working
**Expected Endpoint**: `POST /api/v2/account/apitoken`

**Response**:
```json
{
  "record": {
    "apitoken": "new_generated_token_here"
  }
}
```

**Used By**:
- `/account/settings/api` (ApiSettings.vue)
- Via component: `src/components/account/APIKeyForm.vue`

---

### 7. Account Deletion

**Expected Endpoint**: `POST /api/v2/account/close`

**Request**:
```json
{
  "password": "current_password",
  "confirmation": "DELETE MY ACCOUNT"
}
```

**Response**:
```json
{
  "success": "Account scheduled for deletion"
}
```

**Used By**:
- `/account/settings/caution` (CautionZone.vue)
- Via component: `src/components/account/AccountDeleteButtonWithModalForm.vue`

---

## Security Considerations

### Authentication
All endpoints require:
- Valid session cookie
- CSRF token (via `shrimp` parameter)

### Rate Limiting
Recommended limits:
- Password change: 3 attempts per hour
- MFA operations: 5 attempts per 15 minutes
- Session revocation: 10 per minute
- API token generation: 5 per hour

### Validation
- Password strength requirements enforced
- MFA codes must be 6 digits
- Email verification required for sensitive operations

---

## Response Format Standards

### Success Response
```json
{
  "success": "Operation completed successfully",
  "data": {}
}
```

### Error Response
```json
{
  "error": "Error message",
  "field-error": ["field_name", "error_code"]
}
```

This format matches Rodauth's JSON API response pattern and is already handled by frontend schemas.

---

## Implementation Checklist

### High Priority (Blocking UI)
- [ ] `GET /api/v2/account/info` - Account information
- [ ] `GET /api/v2/account/sessions` - Active sessions list
- [ ] `DELETE /api/v2/account/sessions/:id` - Revoke session
- [ ] `GET /api/v2/account/mfa/status` - MFA status

### Medium Priority (Enhanced Features)
- [ ] `POST /api/v2/account/mfa/enable` - Enable MFA
- [ ] `DELETE /api/v2/account/mfa` - Disable MFA
- [ ] `GET /api/v2/account/recovery-codes/count` - Recovery codes count
- [ ] `POST /api/v2/account/recovery-codes/generate` - Generate codes
- [ ] `POST /api/v2/account/password` - Change password

### Low Priority (Existing/Working)
- [x] `POST /api/v2/account/apitoken` - API key (already working)
- [ ] `POST /api/v2/account/close` - Account deletion (verify)

---

## Frontend Error Handling

The frontend uses these composables for API interaction:
- `src/composables/useAccount.ts` - Account information
- `src/composables/useFormSubmission.ts` - Form submissions with validation
- Response schemas: `src/schemas/api/responses.ts`

Error messages are automatically displayed to users via these composables.

---

## Testing Recommendations

### Manual Testing
1. Test each endpoint with valid/invalid data
2. Verify CSRF protection works
3. Test rate limiting
4. Verify session management

### Automated Testing
- Unit tests for each endpoint
- Integration tests for multi-step flows (e.g., MFA setup)
- Security tests for authentication/authorization

---

## Questions for Backend Team

1. **Account Info**: Which endpoint should provide the account creation date and verification status?
2. **Sessions**: Should IP address and location be derived from session data or stored separately?
3. **MFA**: Which MFA methods should be supported initially? (TOTP, WebAuthn, SMS?)
4. **Recovery Codes**: How many codes should be generated? (Suggested: 10)
5. **Rate Limiting**: Are the suggested limits acceptable or should they be adjusted?

---

## Notes

- All timestamps should be in ISO 8601 format (UTC)
- All endpoints use JSON request/response bodies
- Frontend handles both `success` and `error` response formats
- Field-level errors use the `field-error` tuple format: `[field_name, error_code]`
