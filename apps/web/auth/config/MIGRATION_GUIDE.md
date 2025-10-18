# Email Configuration Migration Guide

## Overview

The email configuration has been refactored from a Mailpit-centric approach to a flexible, production-ready system supporting multiple email providers.

## What Changed

### Before
- Hardcoded Mailpit configuration in main config
- Limited to Mailpit for development, "default Rodauth" for production
- No clear provider abstraction
- Configuration scattered throughout main config file

### After
- Modular email delivery system with multiple providers
- Auto-detection of providers based on environment
- Clear separation of concerns
- Comprehensive configuration via environment variables

## Migration Steps

### 1. Update Environment Variables

**Old Mailpit variables:**
```bash
MAILPIT_SMTP_HOST=localhost
MAILPIT_SMTP_PORT=1025
```

**New Mailpit variables:**
```bash
MAILPIT_HOST=localhost  # Note: SMTP_ prefix removed
MAILPIT_PORT=1025
```

### 2. Configure Production Email

**For SendGrid:**
```bash
EMAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=your_api_key_here
EMAIL_FROM=noreply@yourcompany.com
```

**For AWS SES:**
```bash
EMAIL_PROVIDER=ses
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-1
EMAIL_FROM=noreply@yourcompany.com
```

**For Custom SMTP:**
```bash
EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.yourprovider.com
SMTP_PORT=587
SMTP_USERNAME=your_username
SMTP_PASSWORD=your_password
SMTP_TLS=true
EMAIL_FROM=noreply@yourcompany.com
```

### 3. Optional Customizations

```bash
# Custom email settings
EMAIL_SUBJECT_PREFIX="[YourApp] "
EMAIL_DELIVERY_MODE=sync  # or async (future), test

# Logging level for email operations
EMAIL_LOG_LEVEL=info
```

## Backward Compatibility

The new system maintains backward compatibility with existing deployments:

- **No environment variables**: Defaults to logger in test, auto-detects in other environments
- **Existing MAILPIT_SMTP_HOST**: Will be detected and used (though deprecated)
- **Production without explicit config**: Falls back to logger with warnings

## Testing the Migration

1. **Syntax Check:**
   ```bash
   ruby -c apps/web/auth/config/email.rb
   ```

2. **Configuration Test:**
   ```bash
   ruby apps/web/auth/config/test_email_config.rb
   ```

3. **Integration Test:**
   ```bash
   # Start your application and trigger a verification email
   # Check logs for provider detection and email delivery status
   ```

## Rollback Plan

If issues arise, you can quickly revert by:

1. Commenting out the new email configuration line in `config.rb`:
   ```ruby
   # Email.configure(self)
   ```

2. Restoring the old inline configuration (available in git history)

## Common Issues

### Provider Not Detected
- **Cause**: Missing required environment variables
- **Solution**: Set `EMAIL_PROVIDER` explicitly or ensure required vars are present

### SMTP Authentication Failures
- **Cause**: Incorrect credentials or TLS settings
- **Solution**: Verify SMTP settings, check TLS requirements

### SendGrid/SES API Errors
- **Cause**: Invalid API keys or insufficient permissions
- **Solution**: Verify API keys and required permissions

## Support

For issues with the migration:
1. Check the application logs for email configuration messages
2. Use the test script to validate configuration
3. Review the EMAIL_CONFIG.md for detailed configuration options
