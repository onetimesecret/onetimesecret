# Audit Logging MVP Plan for Onetimesecret

**Status**: Planning Phase
**Target**: Pre-Enterprise MVP
**Date**: 2025-11-08
**Branch**: `claude/audit-logging-hooks-setup-011CUvwV7c62PZhyyzfHXqum`

---

## Executive Summary

This document outlines a comprehensive audit logging strategy for Onetimesecret, leveraging Rodauth's built-in audit_logging feature as the foundation for enterprise-grade security monitoring. The MVP focuses on tracking critical authentication and secret management events while laying groundwork for future compliance requirements (SOC 2, ISO 27001, GDPR).

**Key Objectives**:
- Track all authentication events (login, logout, account lifecycle)
- Monitor secret access patterns and security events
- Provide customers visibility into their account activity
- Enable security incident investigation and compliance reporting
- Build foundation for future enterprise features (SIEM integration, anomaly detection)

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Rodauth Audit Logging Capabilities](#rodauth-audit-logging-capabilities)
3. [What We Can Track](#what-we-can-track)
4. [What We Should Track (MVP Scope)](#what-we-should-track-mvp-scope)
5. [What Else We Want to Track](#what-else-we-want-to-track)
6. [Data Model & Schema Design](#data-model--schema-design)
7. [UI/UX Planning](#uiux-planning)
8. [Implementation Roadmap](#implementation-roadmap)
9. [Technical Considerations](#technical-considerations)
10. [Success Metrics](#success-metrics)

---

## Current State Analysis

### Existing Authentication System

Onetimesecret currently uses a **custom authentication framework** (NOT Rodauth):
- **Storage**: Redis-based via Familia::Horreum ORM
- **Models**: Customer, Session, Secret, Metadata
- **Authentication Logic**: Located in `apps/api/v2/logic/authentication/`
- **Password Handling**: BCrypt with cost factor 12

### Current Logging Infrastructure

**Existing Log Messages** (via `OT.info`, `OT.ld`, `OT.le`):
```ruby
# Authentication Events
[login-success]                    # Successful login
[login-failure]                    # Failed login attempt
[login-pending-customer]          # Pending email verification
[new-customer]                    # Account creation
[destroy-account]                 # Account deletion
[destroy-session]                 # Logout

# Password Management
[ResetPasswordRequest]            # Password reset email sent
[valid_reset_secret!]             # Reset token validation

# Secret Operations
[reveal_secret]                   # Secret viewed
[verification]                    # Email verification via secret
[deliver-by-email]                # Secret sent via email
```

**Current Limitations**:
- ✗ No structured audit log table/storage
- ✗ No queryable audit trail
- ✗ No user-facing audit log viewer
- ✗ Logs mixed with application logs
- ✗ No retention policy
- ✗ No compliance reporting capabilities
- ✗ Limited metadata capture (IP, user agent inconsistent)

---

## Rodauth Audit Logging Capabilities

### How Rodauth Audit Logging Works

Rodauth's `audit_logging` feature provides **automatic, hook-based audit logging**:

1. **Automatic Integration**: Hooks into ALL `after_*` hooks across all Rodauth features
2. **Database-Backed**: Stores audit logs in a dedicated table (`account_authentication_audit_logs`)
3. **Zero Configuration**: Works out-of-the-box with sensible defaults
4. **Customizable**: Supports custom messages and metadata per action

### Database Schema

```sql
CREATE TABLE account_authentication_audit_logs (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT NOT NULL,
  message VARCHAR(255) NOT NULL,
  metadata JSONB,  -- or JSON/TEXT depending on database
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_account_id ON account_authentication_audit_logs(account_id);
CREATE INDEX idx_audit_created_at ON account_authentication_audit_logs(created_at);
```

### Configuration Methods

```ruby
plugin :rodauth do
  enable :audit_logging

  # Table/column customization
  audit_logging_table :account_authentication_audit_logs
  audit_logging_account_id_column :account_id
  audit_logging_message_column :message
  audit_logging_metadata_column :metadata

  # Default metadata (included in every log)
  audit_log_metadata_default do
    {
      ip_address: request.ip,
      user_agent: request.user_agent,
      session_id: session_value, # session ID
    }
  end

  # Action-specific custom messages
  audit_log_message_for :login do
    "User logged in from #{request.ip}"
  end

  # Action-specific metadata
  audit_log_metadata_for :login do
    {
      remember_me: param_or_nil('remember'),
      two_factor_used: uses_two_factor_authentication?
    }
  end
end
```

---

## What We Can Track

### Rodauth Features & Their Audit Hooks

Based on Rodauth's comprehensive feature set, here are the available `after_*` hooks that automatically trigger audit logging:

#### 1. Base Authentication (Core Features)

**Login Feature**:
- `after_login` - Successful login
- `after_login_failure` - Failed login attempt

**Logout Feature**:
- `after_logout` - User logout

**Create Account Feature**:
- `after_create_account` - New account created

**Close Account Feature**:
- `after_close_account` - Account closed/deleted

#### 2. Account Management

**Verify Account Feature**:
- `after_verify_account` - Email verification completed

**Change Login Feature**:
- `after_login_change` - Email/username changed

**Verify Login Change Feature**:
- `after_verify_login_change` - New email verified

**Change Password Feature**:
- `after_change_password` - Password successfully changed

**Reset Password Feature**:
- `after_reset_password` - Password reset completed

#### 3. Multifactor Authentication (MFA)

**OTP (TOTP) Feature**:
- `after_otp_setup` - TOTP authentication enabled
- `after_otp_disable` - TOTP authentication disabled
- `after_otp_authentication` - Successful TOTP authentication
- `after_otp_authentication_failure` - Failed TOTP attempt

**Recovery Codes Feature**:
- `after_recovery_codes_add` - Recovery codes generated
- `after_recovery_auth` - Login via recovery code

**SMS Codes Feature**:
- `after_sms_request` - SMS code sent
- `after_sms_auth` - SMS authentication successful
- `after_sms_disable` - SMS authentication disabled

**WebAuthn Feature**:
- `after_webauthn_setup` - WebAuthn credential added
- `after_webauthn_auth` - WebAuthn authentication successful
- `after_webauthn_remove` - WebAuthn credential removed

#### 4. Session & Security Features

**Lockout Feature**:
- `after_account_lockout` - Account locked due to failed attempts
- `after_unlock_account` - Account unlocked

**Session Expiration Feature**:
- Session expiration events (automatic via hooks)

**Active Sessions Feature**:
- `after_global_logout` - All sessions logged out

**Remember Feature**:
- `after_remember` - "Remember me" token created
- `after_clear_remember` - Remember token cleared

#### 5. Alternative Authentication

**Email Authentication Feature**:
- `after_email_auth_request` - Email login link sent
- `after_email_auth` - Login via email link

**Password Expiration Feature**:
- `after_password_expiration_check` - Password expiration detected

---

## What We Should Track (MVP Scope)

### Priority 1: Critical Security Events (Must-Have)

These events are essential for security monitoring and incident response:

| Event Category | Event | Rodauth Hook | Why Critical |
|----------------|-------|--------------|--------------|
| **Authentication** | Successful login | `after_login` | Track legitimate access |
| | Failed login | `after_login_failure` | Detect brute force attacks |
| | Logout | `after_logout` | Session lifecycle tracking |
| **Account Lifecycle** | Account created | `after_create_account` | New user registration |
| | Account verified | `after_verify_account` | Email confirmation |
| | Account closed | `after_close_account` | User deletion/churn |
| **Password Security** | Password changed | `after_change_password` | Credential updates |
| | Password reset requested | Custom hook | Password recovery attempts |
| | Password reset completed | `after_reset_password` | Password recovery success |
| **Session Security** | Session expired | Custom hook | Automatic session cleanup |
| | Session replaced | Custom hook | Session fixation protection |

**Metadata to Capture** (Priority 1):
```json
{
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0...",
  "session_id": "abc123...",
  "timestamp": "2025-11-08T12:34:56Z",
  "success": true,
  "event_type": "authentication.login"
}
```

### Priority 2: Account Management Events (Should-Have)

| Event Category | Event | Rodauth Hook | Business Value |
|----------------|-------|--------------|----------------|
| **Profile Changes** | Email changed | `after_login_change` | Account takeover detection |
| | Email change verified | `after_verify_login_change` | Track email updates |
| **API Access** | API token generated | Custom hook | API security monitoring |
| | API token used | Custom hook | API usage patterns |
| **Plan Changes** | Plan upgraded | Custom hook | Revenue tracking |
| | Plan downgraded | Custom hook | Churn signals |

### Priority 3: Secret Operations (High-Value Beyond Rodauth)

These are NOT Rodauth events but critical to Onetimesecret's core business:

| Event | Current Logging | Why Track |
|-------|-----------------|-----------|
| Secret created | Counters only | Usage patterns, compliance |
| Secret viewed | `[reveal_secret]` | Security monitoring, one-time proof |
| Secret burned (viewed) | Implicit | Lifecycle completion |
| Secret expired | None | Automatic cleanup tracking |
| Secret sent via email | `[deliver-by-email]` | Delivery confirmation |
| Failed passphrase attempt | `[reveal_secret]` | Brute force on secrets |
| Metadata viewed | `[show_metadata]` | Access patterns |

**Extended Metadata for Secrets**:
```json
{
  "secret_key": "abc123",
  "secret_shortkey": "abc123",
  "action": "secret_viewed",
  "viewer_ip": "192.168.1.100",
  "viewer_session": "xyz789",
  "viewer_custid": "user@example.com",
  "is_owner": false,
  "had_passphrase": true,
  "passphrase_correct": true,
  "share_domain": "https://onetimesecret.com",
  "ttl_remaining": 3600
}
```

### MVP Scope Decision Matrix

| Feature | P1 (MVP) | P2 (Post-MVP) | P3 (Enterprise) |
|---------|----------|---------------|-----------------|
| Login/Logout tracking | ✅ | | |
| Failed login tracking | ✅ | | |
| Account lifecycle | ✅ | | |
| Password changes | ✅ | | |
| Secret views | ✅ | | |
| Failed secret passphrase | ✅ | | |
| Email changes | | ✅ | |
| API token events | | ✅ | |
| MFA events (OTP) | | ✅ | |
| WebAuthn events | | | ✅ |
| Session anomaly detection | | | ✅ |
| Geographic tracking | | | ✅ |
| SIEM integration | | | ✅ |

---

## What Else We Want to Track

### Beyond Rodauth: Business & Security Intelligence

#### 1. Secret Lifecycle Events (High Priority)

```ruby
# New audit events to implement
class V2::AuditLog
  EVENTS = {
    # Secrets
    'secret.created' => 'Secret created',
    'secret.viewed' => 'Secret viewed',
    'secret.burned' => 'Secret burned (viewed once)',
    'secret.expired' => 'Secret expired unviewed',
    'secret.passphrase_failed' => 'Failed passphrase attempt',
    'secret.shared_via_email' => 'Secret link sent via email',

    # Metadata
    'metadata.viewed' => 'Secret metadata viewed',
    'metadata.created' => 'Secret metadata created',

    # API
    'api.token_generated' => 'API token generated',
    'api.token_used' => 'API authentication',
    'api.rate_limit_exceeded' => 'Rate limit exceeded',

    # Account
    'account.email_verification_sent' => 'Verification email sent',
    'account.locale_changed' => 'Language preference updated',
    'account.plan_changed' => 'Subscription plan changed',

    # Custom Domains (Enterprise)
    'domain.added' => 'Custom domain added',
    'domain.verified' => 'Custom domain verified',
    'domain.removed' => 'Custom domain removed',

    # Security
    'security.suspicious_activity' => 'Suspicious activity detected',
    'security.rate_limit_hit' => 'Rate limit triggered',
  }
end
```

#### 2. Rate Limiting & Abuse Detection

Current rate limiting exists but isn't audited:
- `authenticate_session` (login attempts)
- `create_account` (signup attempts)
- `show_secret` (secret access)
- `failed_passphrase` (passphrase guessing)
- `forgot_password_request` (password reset requests)

**Audit Log Integration**:
```ruby
# When rate limit is hit, log the event
after_rate_limit_exceeded do |action|
  audit_log(
    event: 'security.rate_limit_exceeded',
    metadata: {
      action: action,
      ip_address: request.ip,
      session_id: session_id
    }
  )
end
```

#### 3. Geographic & Device Intelligence (Future)

Not in MVP but valuable for enterprise:
```json
{
  "location": {
    "country": "US",
    "region": "California",
    "city": "San Francisco",
    "timezone": "America/Los_Angeles"
  },
  "device": {
    "type": "desktop",
    "os": "macOS",
    "browser": "Chrome 120.0"
  },
  "anomaly_score": 0.23,  // ML-based risk score
  "new_device": true,
  "new_location": true
}
```

#### 4. Compliance & Legal Events

For SOC 2, GDPR, HIPAA compliance:
```ruby
# GDPR-specific events
'privacy.data_export_requested' => 'User requested data export',
'privacy.data_deleted' => 'User data permanently deleted',
'privacy.consent_given' => 'Privacy consent granted',
'privacy.consent_withdrawn' => 'Privacy consent withdrawn',

# Admin actions (Colonel role)
'admin.customer_viewed' => 'Admin viewed customer account',
'admin.setting_changed' => 'System setting modified',
'admin.support_access' => 'Admin accessed customer data for support',
```

---

## Data Model & Schema Design

### Design Decision: PostgreSQL vs Redis

| Aspect | PostgreSQL | Redis | Recommendation |
|--------|-----------|-------|----------------|
| **Query Flexibility** | ✅ SQL queries, indexes | ❌ Limited querying | **PostgreSQL** |
| **Data Retention** | ✅ Long-term storage | ⚠️ Memory constraints | **PostgreSQL** |
| **Performance** | ✅ Good with indexes | ✅ Excellent | **PostgreSQL** |
| **Compliance** | ✅ ACID guarantees | ❌ Eventual consistency | **PostgreSQL** |
| **Current Stack** | ❌ New dependency | ✅ Already in use | **PostgreSQL** |
| **Rodauth Support** | ✅ Native (Sequel) | ❌ Not supported | **PostgreSQL** |

**Decision**: Use **PostgreSQL** for audit logs. This aligns with:
- Rodauth's native Sequel/PostgreSQL support
- Long-term retention requirements
- Complex querying needs for UI and reporting
- Industry best practices for audit logging

### Schema Design

#### Primary Audit Log Table

```sql
-- Main audit log table (handles both Rodauth and custom events)
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,

  -- Who
  account_id BIGINT,  -- NULL for anonymous events
  account_email VARCHAR(255),  -- Denormalized for deleted accounts

  -- What
  event_type VARCHAR(100) NOT NULL,  -- e.g., 'authentication.login'
  event_category VARCHAR(50) NOT NULL,  -- 'authentication', 'secret', 'account'
  message TEXT NOT NULL,  -- Human-readable message

  -- When
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),

  -- Where/How
  ip_address INET,
  user_agent TEXT,
  session_id VARCHAR(255),

  -- Details (flexible JSON)
  metadata JSONB,

  -- Audit trail integrity
  checksum VARCHAR(64)  -- SHA-256 of row data for tamper detection
);

-- Indexes for performance
CREATE INDEX idx_audit_account_id ON audit_logs(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_audit_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_event_type ON audit_logs(event_type);
CREATE INDEX idx_audit_event_category ON audit_logs(event_category);
CREATE INDEX idx_audit_ip_address ON audit_logs(ip_address) WHERE ip_address IS NOT NULL;

-- GIN index for JSONB metadata queries
CREATE INDEX idx_audit_metadata ON audit_logs USING GIN(metadata);

-- Composite index for common queries
CREATE INDEX idx_audit_account_created ON audit_logs(account_id, created_at DESC)
  WHERE account_id IS NOT NULL;
```

#### Rodauth Integration Compatibility

To use Rodauth's audit_logging feature with our custom table:

```ruby
plugin :rodauth do
  enable :audit_logging

  # Map to our custom table schema
  audit_logging_table :audit_logs
  audit_logging_account_id_column :account_id
  audit_logging_message_column :message
  audit_logging_metadata_column :metadata

  # Default metadata for all events
  audit_log_metadata_default do
    {
      ip_address: request.ip,
      user_agent: request.user_agent,
      session_id: session[:session_id],
      event_category: 'authentication'  # Override per event
    }
  end

  # Store IP and user_agent at top level too
  before do
    # Populate our custom columns from metadata
    # This happens via database trigger or application logic
  end
end
```

#### Supporting Tables (Optional - Post-MVP)

```sql
-- Session audit (detailed session tracking)
CREATE TABLE audit_sessions (
  id BIGSERIAL PRIMARY KEY,
  session_id VARCHAR(255) UNIQUE NOT NULL,
  account_id BIGINT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  last_activity TIMESTAMP NOT NULL DEFAULT NOW(),
  expired_at TIMESTAMP,
  ip_address INET,
  user_agent TEXT,
  login_method VARCHAR(50),  -- 'password', 'email_link', 'webauthn'
  mfa_used BOOLEAN DEFAULT FALSE
);

-- Secret access audit (high-detail secret tracking)
CREATE TABLE audit_secret_access (
  id BIGSERIAL PRIMARY KEY,
  secret_key VARCHAR(255) NOT NULL,
  secret_shortkey VARCHAR(20),
  action VARCHAR(50) NOT NULL,  -- 'created', 'viewed', 'burned', 'expired'

  -- Actor
  viewer_account_id BIGINT,
  viewer_session_id VARCHAR(255),
  viewer_ip INET,

  -- Secret details (snapshot at time of access)
  had_passphrase BOOLEAN,
  passphrase_correct BOOLEAN,
  is_owner BOOLEAN,
  ttl_remaining INTEGER,  -- seconds

  created_at TIMESTAMP NOT NULL DEFAULT NOW(),

  -- Metadata
  metadata JSONB
);

CREATE INDEX idx_secret_access_key ON audit_secret_access(secret_key);
CREATE INDEX idx_secret_access_created ON audit_secret_access(created_at DESC);
CREATE INDEX idx_secret_access_viewer ON audit_secret_access(viewer_account_id)
  WHERE viewer_account_id IS NOT NULL;
```

### Data Retention Policy

```sql
-- Partition by month for efficient retention management
CREATE TABLE audit_logs_2025_11 PARTITION OF audit_logs
  FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');

-- Automatic partitioning (via pg_partman or cron job)
-- Retention: Keep 90 days for regular users, 1 year for enterprise
```

**Retention Tiers**:
- **Free/Basic Plans**: 30 days
- **Premium Plans**: 90 days
- **Enterprise Plans**: 1 year (configurable)
- **Compliance Mode**: 7 years (GDPR, SOX)

### ORM Integration Options

Since onetimesecret uses Redis/Familia, we need to integrate PostgreSQL:

**Option 1: Sequel (Rodauth's Native ORM)**
```ruby
# Gemfile
gem 'sequel'
gem 'pg'

# lib/onetime/db.rb
require 'sequel'

DB = Sequel.connect(ENV['DATABASE_URL'] || 'postgres://localhost/onetimesecret_audit')

# Model
class AuditLog < Sequel::Model
  plugin :timestamps, update_on_create: true

  def self.log(event_type:, account_id: nil, message:, metadata: {})
    create(
      event_type: event_type,
      event_category: event_type.split('.').first,
      account_id: account_id,
      message: message,
      metadata: Sequel.pg_jsonb(metadata)
    )
  end
end
```

**Option 2: ActiveRecord (If Moving Towards Rails)**
```ruby
class AuditLog < ActiveRecord::Base
  belongs_to :account, optional: true

  scope :recent, -> { order(created_at: :desc).limit(100) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :by_category, ->(category) { where(event_category: category) }
end
```

**Recommendation**: Use **Sequel** to maintain consistency with Rodauth and avoid ActiveRecord overhead.

---

## UI/UX Planning

### User-Facing Audit Log Features

#### 1. Account Activity Page

**Route**: `/account/activity` or `/account/security`

**Purpose**: Give users visibility into their account security

**Layout**:
```
┌─────────────────────────────────────────────────────────────┐
│  Account Activity                                  🔒 Secure │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Filter by: [All Activity ▼]  [Last 30 Days ▼]  [Search...] │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ✅ Successful login                              Today  │ │
│  │    From: 192.168.1.100 (San Francisco, CA)      10:23  │ │
│  │    Device: Chrome on macOS                              │ │
│  │    [Not you? Secure your account →]                     │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 👁️  Secret viewed                            Yesterday  │ │
│  │    Secret: abc123                               14:32   │ │
│  │    From: 203.0.113.45 (London, UK)                      │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ⚠️  Failed login attempt                    2 days ago  │ │
│  │    From: 198.51.100.42 (Unknown)             09:15      │ │
│  │    Reason: Incorrect password                           │ │
│  │    [Review security settings →]                         │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Load More Activity]                                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Key Features**:
- **Timeline View**: Reverse chronological order (newest first)
- **Filtering**: By event type, date range, IP address
- **Search**: Full-text search in messages
- **Visual Indicators**: Icons/colors for event severity
  - ✅ Green: Successful/normal actions
  - ⚠️ Yellow: Warnings (failed attempts, suspicious activity)
  - 🔴 Red: Critical (account lockout, password reset)
- **Contextual Actions**: Quick links to secure account or change password
- **Export**: Download as CSV/JSON (enterprise feature)

#### 2. Event Detail Modal

When clicking an event:
```
┌─────────────────────────────────────────────────────┐
│  Event Details                                  [X] │
├─────────────────────────────────────────────────────┤
│                                                      │
│  Event Type: Successful Login                       │
│  Date: November 8, 2025 at 10:23:45 AM PST          │
│                                                      │
│  Location Details:                                  │
│    IP Address: 192.168.1.100                        │
│    City: San Francisco, CA                          │
│    Country: United States                           │
│                                                      │
│  Device Information:                                │
│    Browser: Chrome 120.0.6099.109                   │
│    OS: macOS 14.1                                   │
│    Device Type: Desktop                             │
│                                                      │
│  Session Information:                               │
│    Session ID: abc123xyz (current session)          │
│    Login Method: Password                           │
│                                                      │
│  [This wasn't me - Secure my account]              │
│                                                      │
└─────────────────────────────────────────────────────┘
```

#### 3. Security Dashboard (Enterprise)

**Route**: `/account/security/dashboard`

**Widgets**:
- Active Sessions (with "Log out all other sessions" button)
- Recent Login Locations (map view)
- Failed Login Attempts (graph over time)
- Secret Activity Summary
- Security Score/Health Indicator

#### 4. Email Notifications for Critical Events

Send email alerts for:
- ✅ Successful login from new device/location
- ⚠️ Failed login attempts (>3 in 5 minutes)
- 🔴 Password changed
- 🔴 Email changed
- 🔴 Account locked
- 🔴 Recovery email sent

**Email Template**:
```
Subject: New login to your Onetimesecret account

Hi there,

We detected a new login to your account:

  Time: November 8, 2025 at 10:23 AM PST
  Location: San Francisco, CA
  Device: Chrome on macOS
  IP Address: 192.168.1.100

If this was you, you can safely ignore this email.

If this wasn't you, please secure your account immediately:
https://onetimesecret.com/account/security

[Secure My Account]

---
You can manage your security settings at:
https://onetimesecret.com/account/security
```

### API Endpoints for Audit Logs

#### REST API

```ruby
# List audit logs for current user
GET /api/v2/account/activity
Query params:
  - limit (default: 50, max: 100)
  - offset (pagination)
  - event_type (filter)
  - start_date, end_date (ISO 8601)
  - category (authentication, secret, account)

Response:
{
  "records": [
    {
      "id": 12345,
      "event_type": "authentication.login",
      "message": "Successful login",
      "created_at": "2025-11-08T10:23:45Z",
      "ip_address": "192.168.1.100",
      "metadata": {
        "user_agent": "Mozilla/5.0...",
        "session_id": "abc123"
      }
    }
  ],
  "total": 347,
  "limit": 50,
  "offset": 0
}

# Get specific event details
GET /api/v2/account/activity/:id

# Export audit logs (enterprise)
GET /api/v2/account/activity/export
Query params:
  - format (csv, json)
  - start_date, end_date

# Admin endpoints (colonel role)
GET /api/v2/admin/audit_logs
Query params:
  - account_id (filter by customer)
  - event_type
  - start_date, end_date
```

### UI Components Needed

**New Files to Create**:
```
apps/web/views/
  account/
    activity.erb                 # Main activity timeline
    _activity_event.erb          # Event list item partial
    _activity_filters.erb        # Filter controls
    security_dashboard.erb       # Enterprise dashboard

apps/web/controllers/
  account/
    activity_controller.rb       # Handle activity page

apps/api/v2/logic/
  account/
    get_activity.rb             # Fetch audit logs
    export_activity.rb          # CSV/JSON export

apps/api/v2/routes/
  account_activity_routes.rb    # API routes

public/web/css/
  account_activity.css          # Styles for timeline

public/web/js/
  account_activity.js           # Interactive filtering
```

### Mobile-First Design Considerations

```css
/* Responsive timeline */
.activity-timeline {
  /* Mobile: Stack vertically */
  @media (max-width: 768px) {
    .event-details {
      display: block;
    }
    .event-metadata {
      margin-top: 8px;
    }
  }

  /* Desktop: Side-by-side */
  @media (min-width: 769px) {
    .event-item {
      display: grid;
      grid-template-columns: 1fr 200px;
    }
  }
}
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

**Goal**: Set up infrastructure and basic Rodauth audit logging

**Tasks**:
1. ✅ Add PostgreSQL to project
   - Update Gemfile: `sequel`, `pg`
   - Create database connection layer
   - Test connection in development/test/production

2. ✅ Create database migration
   ```bash
   rake db:create_migration NAME=create_audit_logs
   ```
   - Define `audit_logs` table schema
   - Add indexes
   - Run migration: `rake db:migrate`

3. ✅ Set up Sequel ORM
   - Create `lib/onetime/db.rb`
   - Create `AuditLog` model
   - Write basic tests

4. ✅ Rodauth Integration (if implementing Rodauth)
   - Add `rodauth` gem
   - Configure rodauth plugin
   - Enable `audit_logging` feature
   - Test basic login/logout logging

5. ✅ Custom Audit Logger (if NOT using Rodauth yet)
   ```ruby
   # lib/onetime/audit_logger.rb
   module Onetime
     class AuditLogger
       def self.log(event_type:, account_id: nil, message:, metadata: {})
         AuditLog.create(
           event_type: event_type,
           event_category: event_type.split('.').first,
           account_id: account_id,
           account_email: account&.custid,
           message: message,
           ip_address: metadata[:ip_address],
           user_agent: metadata[:user_agent],
           session_id: metadata[:session_id],
           metadata: Sequel.pg_jsonb(metadata),
           created_at: Time.now.utc
         )
       end
     end
   end
   ```

**Deliverables**:
- [ ] PostgreSQL integration working
- [ ] `audit_logs` table created
- [ ] Basic audit log model
- [ ] Unit tests passing

### Phase 2: Authentication Events (Week 3-4)

**Goal**: Log all authentication-related events

**Tasks**:
1. ✅ Instrument login flow
   ```ruby
   # apps/api/v2/logic/authentication/authenticate_session.rb
   def process
     if success?
       # Existing code...

       # NEW: Log successful login
       Onetime::AuditLogger.log(
         event_type: 'authentication.login',
         account_id: cust.custid,
         message: "Successful login from #{sess.ipaddress}",
         metadata: {
           ip_address: sess.ipaddress,
           user_agent: sess.useragent,
           session_id: sess.sessid,
           stay: @stay
         }
       )
     else
       # NEW: Log failed login
       Onetime::AuditLogger.log(
         event_type: 'authentication.login_failure',
         account_id: @potential_custid,
         message: "Failed login attempt",
         metadata: {
           ip_address: sess.ipaddress,
           user_agent: sess.useragent,
           attempted_email: @potential_custid
         }
       )
     end
   end
   ```

2. ✅ Instrument logout flow
3. ✅ Instrument account creation
4. ✅ Instrument password reset
5. ✅ Instrument password change
6. ✅ Instrument account deletion

**Deliverables**:
- [ ] All auth events logged
- [ ] Integration tests passing
- [ ] Logs viewable in database

### Phase 3: Secret Events (Week 5-6)

**Goal**: Track secret lifecycle and access patterns

**Tasks**:
1. ✅ Log secret creation
   ```ruby
   # After secret creation in BaseSecretAction
   Onetime::AuditLogger.log(
     event_type: 'secret.created',
     account_id: cust.custid,
     message: "Secret created (#{secret.shortkey})",
     metadata: {
       secret_key: secret.key,
       secret_shortkey: secret.shortkey,
       ttl: secret.lifespan,
       has_passphrase: secret.has_passphrase?,
       share_domain: secret.share_domain
     }
   )
   ```

2. ✅ Log secret views
3. ✅ Log failed passphrase attempts
4. ✅ Log secret expiration (background job)
5. ✅ Log email delivery

**Deliverables**:
- [ ] Secret events logged
- [ ] Background job for expiration tracking
- [ ] Tests passing

### Phase 4: UI Implementation (Week 7-8)

**Goal**: Build user-facing activity page

**Tasks**:
1. ✅ Create `/account/activity` route
2. ✅ Build activity timeline view
3. ✅ Implement filtering/search
4. ✅ Add event detail modal
5. ✅ Responsive design
6. ✅ Add to account navigation menu

**Deliverables**:
- [ ] Activity page accessible to logged-in users
- [ ] Timeline displays recent events
- [ ] Filters working
- [ ] Mobile-friendly UI

### Phase 5: API & Export (Week 9-10)

**Goal**: Provide programmatic access to audit logs

**Tasks**:
1. ✅ Create API endpoints
   - `GET /api/v2/account/activity`
   - `GET /api/v2/account/activity/:id`
   - `GET /api/v2/account/activity/export`

2. ✅ Implement CSV export
3. ✅ Implement JSON export
4. ✅ Add API authentication
5. ✅ Rate limiting on export endpoints
6. ✅ API documentation

**Deliverables**:
- [ ] API endpoints functional
- [ ] Export working (CSV + JSON)
- [ ] API docs updated

### Phase 6: Enterprise Features (Week 11-12)

**Goal**: Advanced features for enterprise customers

**Tasks**:
1. ✅ Security dashboard
2. ✅ Email notifications
3. ✅ Geographic enrichment (IP → location)
4. ✅ Device fingerprinting
5. ✅ Admin audit log viewer (colonel role)
6. ✅ Retention policy enforcement
7. ✅ Anomaly detection (basic heuristics)

**Deliverables**:
- [ ] Dashboard live
- [ ] Email alerts working
- [ ] Admin tools functional

### Phase 7: Testing & Hardening (Week 13-14)

**Goal**: Production readiness

**Tasks**:
1. ✅ Performance testing (query optimization)
2. ✅ Load testing (simulate 10k events/sec)
3. ✅ Security audit (SQL injection, XSS)
4. ✅ Data privacy review (GDPR compliance)
5. ✅ Backup/restore procedures
6. ✅ Monitoring & alerting setup
7. ✅ Documentation (user guide, admin guide)

**Deliverables**:
- [ ] Performance benchmarks met
- [ ] Security review passed
- [ ] Docs published

---

## Technical Considerations

### 1. Database Migration Strategy

**Challenge**: Onetimesecret uses Redis; adding PostgreSQL is new.

**Approach**:
- **Dual persistence**: Keep Redis for existing data, PostgreSQL for audit logs only
- **Migration tool**: Sequel Migrations
- **Rollback plan**: Each migration reversible

```ruby
# db/migrations/001_create_audit_logs.rb
Sequel.migration do
  up do
    create_table(:audit_logs) do
      primary_key :id, type: :Bignum
      # ... full schema
    end
  end

  down do
    drop_table(:audit_logs)
  end
end
```

### 2. Performance Considerations

**Write Performance**:
- Audit logging is write-heavy (1000s of events/day)
- **Mitigation**: Async logging via background job queue
  ```ruby
  # Don't block request for audit logging
  Sidekiq::Client.push(
    'class' => AuditLogWorker,
    'args' => [event_data]
  )
  ```

**Read Performance**:
- Activity page needs fast queries
- **Mitigation**: Proper indexing, pagination, caching
  ```ruby
  # Cache recent activity for 5 minutes
  Rails.cache.fetch("activity:#{account_id}:recent", expires_in: 5.minutes) do
    AuditLog.for_account(account_id).recent.limit(50).all
  end
  ```

**Query Examples**:
```sql
-- Efficient: Uses idx_audit_account_created
SELECT * FROM audit_logs
WHERE account_id = 123
ORDER BY created_at DESC
LIMIT 50;

-- Efficient: Uses idx_audit_event_type
SELECT COUNT(*) FROM audit_logs
WHERE event_type = 'authentication.login_failure'
  AND created_at > NOW() - INTERVAL '1 hour';

-- Efficient: Uses GIN index on metadata
SELECT * FROM audit_logs
WHERE metadata @> '{"ip_address": "192.168.1.100"}';
```

### 3. Data Privacy & GDPR Compliance

**Personal Data in Audit Logs**:
- Email addresses (account_email)
- IP addresses
- User agents
- Session IDs

**GDPR Requirements**:
- Right to access (✅ covered by activity page)
- Right to export (✅ CSV/JSON export)
- Right to erasure (⚠️ conflicts with audit integrity)

**Approach**:
- **Pseudonymization**: Replace email with account ID after 90 days
- **Retention limits**: Auto-delete after retention period
- **Audit trail exception**: Legal basis to retain critical security events

```sql
-- Pseudonymize old logs (run monthly)
UPDATE audit_logs
SET account_email = 'deleted-user@onetimesecret.com',
    metadata = metadata - 'user_agent'  -- Remove PII from metadata
WHERE created_at < NOW() - INTERVAL '90 days'
  AND account_email != 'deleted-user@onetimesecret.com';
```

### 4. Security Considerations

**SQL Injection**:
- ✅ Use Sequel's parameterized queries (built-in protection)
- ❌ Never interpolate user input directly

**Audit Log Tampering**:
- Add `checksum` column (SHA-256 hash of row)
- Verify checksum on read to detect tampering
  ```ruby
  def calculate_checksum
    data = "#{id}:#{account_id}:#{event_type}:#{created_at}:#{message}"
    Digest::SHA256.hexdigest(data)
  end

  def verify_integrity!
    raise "Audit log tampered!" unless checksum == calculate_checksum
  end
  ```

**Access Control**:
- Users can only view their own logs
- Admins (colonels) can view all logs
- API requires authentication

### 5. Monitoring & Alerting

**Metrics to Track**:
- Audit log write rate (events/sec)
- Failed login rate (potential attacks)
- Database size growth (partition management)
- Query performance (slow query log)

**Alerts**:
- Failed login spike (>100/min) → potential DDoS
- Audit log write failures → database issues
- Disk space < 20% → partition cleanup needed

### 6. Scalability Plan

**Current Scale**: Assume 10k users, 1M events/month

**Future Scale**: 100k users, 100M events/month

**Scaling Strategies**:
1. **Partitioning**: Monthly partitions (already planned)
2. **Archival**: Move old logs to cold storage (S3)
3. **Read replicas**: PostgreSQL read replicas for query load
4. **Sharding**: Shard by account_id (if needed)

---

## Success Metrics

### MVP Launch Metrics

**Adoption**:
- [ ] 50% of active users view activity page in first month
- [ ] <1% support tickets about audit logs (indicates good UX)

**Performance**:
- [ ] Activity page loads in <500ms (p95)
- [ ] Audit logging doesn't slow down auth by >10ms
- [ ] Zero audit log write failures

**Security**:
- [ ] 100% of authentication events logged
- [ ] Failed login detection catches 5+ brute force attempts
- [ ] Email alerts sent for 100% of critical events

### Post-MVP Goals

**Engagement**:
- [ ] Enterprise customers use export feature monthly
- [ ] Security dashboard becomes top-5 visited page

**Business Impact**:
- [ ] Audit logging becomes enterprise plan differentiator
- [ ] Supports SOC 2 compliance certification
- [ ] Reduces account compromise incidents by 30%

---

## Next Steps

### Immediate Actions (This Sprint)

1. **Decision**: Confirm PostgreSQL as audit log store
2. **Spike**: Proof-of-concept Sequel integration (2 days)
3. **Design Review**: Get stakeholder feedback on UI mockups
4. **Estimate**: Refine timeline based on team capacity

### Open Questions

1. **Rodauth Adoption**: Should we migrate entire auth system to Rodauth, or just use audit_logging?
   - **Recommendation**: Phase 1 = Custom audit logger, Phase 2+ = Full Rodauth migration

2. **Real-time vs Batch**: Should audit logging be synchronous or async?
   - **Recommendation**: Async for performance, with fallback to sync for critical events

3. **IP Geolocation**: Use free service (MaxMind) or paid (IPinfo)?
   - **Recommendation**: Start with free MaxMind GeoLite2, upgrade if accuracy issues

4. **Export Limits**: Should free users get exports?
   - **Recommendation**: No exports for free tier, CSV for paid, JSON API for enterprise

---

## Appendix

### A. Useful Resources

- [Rodauth Audit Logging Docs](https://rodauth.jeremyevans.net/rdoc/files/doc/audit_logging_rdoc.html)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
- [GDPR Audit Log Requirements](https://gdpr.eu/article-30-record-of-processing-activities/)
- [Sequel ORM Documentation](https://sequel.jeremyevans.net/)

### B. Database Schema (Full SQL)

See full schema in migration file: `db/migrations/001_create_audit_logs.rb`

### C. API Response Examples

See full API documentation in: `docs/api/audit_logs.md` (to be created)

### D. UI Mockups

See Figma designs: [Link to mockups] (to be created)

---

**Document Version**: 1.0
**Last Updated**: 2025-11-08
**Author**: Claude (AI Planning Assistant)
**Review Status**: Draft - Awaiting Stakeholder Review
