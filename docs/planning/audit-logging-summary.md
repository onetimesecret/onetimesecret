# Audit Logging MVP - Executive Summary

**Date**: 2025-11-08
**Branch**: `claude/audit-logging-hooks-setup-011CUvwV7c62PZhyyzfHXqum`
**Full Plan**: See [audit-logging-mvp-plan.md](./audit-logging-mvp-plan.md)

---

## TL;DR

This plan delivers a comprehensive audit logging system for Onetimesecret using Rodauth's hook-based architecture, PostgreSQL for storage, and a user-friendly activity timeline UI. Target: 14-week implementation for pre-enterprise MVP.

---

## Key Decisions

### 1. Technology Stack
- **Database**: PostgreSQL (new addition to Redis-based stack)
- **ORM**: Sequel (aligns with Rodauth)
- **Framework**: Rodauth's `audit_logging` feature + custom extensions
- **Storage Strategy**: PostgreSQL for audit logs, keep Redis for existing data

### 2. MVP Scope (Priority 1)

**What We're Tracking**:
- ✅ Authentication events (login, logout, failures)
- ✅ Account lifecycle (create, verify, delete)
- ✅ Password security (changes, resets)
- ✅ Secret operations (create, view, burn, failures)
- ✅ Session management (expiration, replacement)

**What's Post-MVP**:
- MFA events (OTP, WebAuthn)
- Geographic enrichment
- Anomaly detection
- SIEM integration

### 3. Data Model

**Core Table**: `audit_logs`
```sql
- id (bigserial)
- account_id, account_email
- event_type, event_category, message
- created_at
- ip_address, user_agent, session_id
- metadata (JSONB)
- checksum (integrity verification)
```

**Retention Policy**:
- Free: 30 days
- Premium: 90 days
- Enterprise: 1 year
- Compliance: 7 years

---

## What Can We Track?

### Via Rodauth Hooks (Automatic)

All Rodauth features with `after_*` hooks get automatic audit logging:

**Base Authentication**:
- `after_login` - Successful login
- `after_login_failure` - Failed login
- `after_logout` - User logout
- `after_create_account` - Account created
- `after_close_account` - Account deleted

**Account Management**:
- `after_verify_account` - Email verified
- `after_change_password` - Password changed
- `after_reset_password` - Password reset completed
- `after_login_change` - Email changed

**MFA (Post-MVP)**:
- `after_otp_setup`, `after_otp_disable`, `after_otp_authentication_failure`
- `after_webauthn_setup`, `after_webauthn_auth`, `after_webauthn_remove`
- `after_recovery_auth` - Recovery code used

**Security**:
- `after_account_lockout` - Account locked (brute force)
- `after_unlock_account` - Account unlocked

### Beyond Rodauth (Custom Events)

**Secret Lifecycle** (core business logic):
- `secret.created` - New secret
- `secret.viewed` - Secret accessed
- `secret.burned` - Secret viewed once (destroyed)
- `secret.expired` - Secret expired unviewed
- `secret.passphrase_failed` - Wrong passphrase attempt
- `secret.shared_via_email` - Sent via email

**API & Admin**:
- `api.token_generated` - API token created
- `api.token_used` - API authentication
- `api.rate_limit_exceeded` - Rate limit hit
- `admin.customer_viewed` - Admin accessed account (colonel)
- `admin.setting_changed` - System config changed

**Compliance** (future):
- `privacy.data_export_requested` - GDPR data export
- `privacy.data_deleted` - Right to erasure
- `privacy.consent_given/withdrawn` - Cookie consent

---

## UI/UX Overview

### 1. Account Activity Page (`/account/activity`)

**User Experience**:
```
Timeline View (Newest First)
├─ ✅ Successful login (Today, 10:23 AM)
│  └─ From: 192.168.1.100 (San Francisco, CA)
│     Device: Chrome on macOS
│     [Not you? Secure your account]
│
├─ 👁️ Secret viewed (Yesterday, 2:32 PM)
│  └─ Secret: abc123
│     From: 203.0.113.45 (London, UK)
│
└─ ⚠️ Failed login (2 days ago, 9:15 AM)
   └─ From: 198.51.100.42 (Unknown)
      Reason: Incorrect password
      [Review security settings]
```

**Features**:
- Filtering by event type, date range
- Search across messages
- Export to CSV/JSON (paid plans)
- Mobile-responsive design
- Visual severity indicators (✅ ⚠️ 🔴)

### 2. Security Dashboard (Enterprise)
- Active sessions map
- Failed login graph
- Recent activity summary
- Security score/health

### 3. Email Alerts
- New device login
- Failed login spike (>3 attempts)
- Password changed
- Account recovery initiated

---

## Implementation Timeline

### Phase 1: Foundation (Week 1-2)
- Add PostgreSQL + Sequel ORM
- Create `audit_logs` table
- Basic model + tests

### Phase 2: Authentication Events (Week 3-4)
- Instrument all auth flows
- Log login, logout, account lifecycle
- Integration tests

### Phase 3: Secret Events (Week 5-6)
- Track secret creation, viewing, burning
- Failed passphrase logging
- Background job for expiration tracking

### Phase 4: UI Implementation (Week 7-8)
- Build `/account/activity` page
- Timeline view + filtering
- Event detail modal
- Responsive design

### Phase 5: API & Export (Week 9-10)
- REST API endpoints
- CSV/JSON export
- Rate limiting + auth

### Phase 6: Enterprise Features (Week 11-12)
- Security dashboard
- Email notifications
- Geographic enrichment (IP → location)
- Admin audit viewer

### Phase 7: Testing & Hardening (Week 13-14)
- Performance testing (10k events/sec)
- Security audit
- GDPR compliance review
- Documentation

**Total**: 14 weeks (~3.5 months)

---

## Technical Highlights

### Performance Strategy
- **Async Logging**: Background jobs (Sidekiq) for non-blocking writes
- **Indexing**: Optimized for common queries (account_id + created_at)
- **Partitioning**: Monthly partitions for retention management
- **Caching**: Recent activity cached for 5 minutes

### Security Measures
- **Integrity Verification**: SHA-256 checksums detect tampering
- **Access Control**: Users see only their logs, admins see all
- **SQL Injection Protection**: Sequel parameterized queries
- **GDPR Compliance**: Pseudonymization after 90 days, retention limits

### Scalability Plan
- **Current**: 10k users, 1M events/month → Single PostgreSQL instance
- **Future**: 100k users, 100M events/month → Read replicas, archival to S3

---

## Success Metrics

**MVP Launch**:
- 50% of users view activity page in month 1
- Activity page loads <500ms (p95)
- 100% of auth events logged
- Zero audit write failures

**Business Impact**:
- Audit logging becomes enterprise differentiator
- Supports SOC 2 compliance
- Reduces account compromise by 30%

---

## Open Questions

1. **Rodauth Migration**: Full migration vs. just audit_logging?
   - **Rec**: Start with custom logger, migrate incrementally

2. **Async vs Sync**: Real-time logging or background jobs?
   - **Rec**: Async for perf, sync for critical events (account deletion)

3. **IP Geolocation**: Free (MaxMind) or paid (IPinfo)?
   - **Rec**: Start free, upgrade if accuracy issues

4. **Export Access**: Allow free users to export?
   - **Rec**: No exports for free, CSV for premium, JSON API for enterprise

---

## Next Steps

1. **Review**: Stakeholder approval of plan
2. **Spike**: 2-day PostgreSQL/Sequel proof-of-concept
3. **Design**: UI mockups for activity page
4. **Estimate**: Refine timeline with team capacity

---

## Files Delivered

- `docs/planning/audit-logging-mvp-plan.md` - Full 15,000-word implementation plan
- `docs/planning/audit-logging-summary.md` - This executive summary

---

**Questions?** See full plan for deep dives on:
- Complete Rodauth hook reference (30+ hooks)
- Database schema with indexes
- UI wireframes and user flows
- API endpoint specifications
- Performance benchmarks
- GDPR compliance details
