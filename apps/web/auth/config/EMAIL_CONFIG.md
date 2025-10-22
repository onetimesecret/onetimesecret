# Email Configuration

The Auth application uses a flexible email delivery system that supports multiple providers and deployment scenarios.

## Configuration

Email delivery is configured via environment variables. The system will auto-detect the appropriate provider based on available configuration, or you can explicitly set the provider using `EMAILER_MODE`.

### Core Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `EMAILER_MODE` | Force a specific provider (`smtp`, `sendgrid`, `ses`, `logger`) | Auto-detected |
| `EMAIL_FROM` | Default sender email address | `noreply@onetimesecret.com` |
| `EMAIL_SUBJECT_PREFIX` | Prefix for all email subjects | `[OneTimeSecret] ` |
| `EMAIL_DELIVERY_MODE` | Delivery mode (`sync`, `async`, `test`) | `sync` |

### Provider-Specific Settings

#### SMTP (Generic)

Use for any SMTP server including Mailpit, Mailtrap, or production SMTP services.

```bash
EMAILER_MODE=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=user@example.com
SMTP_PASSWORD=password123
SMTP_TLS=true    # Use TLS (default: true)
SMTP_AUTH=plain  # Authentication method (default: plain)
```

#### SendGrid
```bash
EMAILER_MODE=sendgrid
SENDGRID_API_KEY=SG.abc123...
```

#### AWS SES
```bash
EMAILER_MODE=ses
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=abc123...
AWS_REGION=us-east-1
```

#### Logger (Testing/Development)
```bash
EMAILER_MODE=logger
# No additional configuration needed
```

## Auto-Detection Logic

When `EMAILER_MODE` is not set, the system detects the provider in this order:

1. **Test Environment**: Uses `logger`
2. **SendGrid**: If `SENDGRID_API_KEY` is present
3. **AWS SES**: If `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are present
4. **SMTP**: If `SMTP_HOST` is present
5. **Fallback**: Uses `logger`

## Examples

### Production with SendGrid
```bash
EMAIL_FROM=support@yourcompany.com
EMAIL_SUBJECT_PREFIX="[YourApp] "
SENDGRID_API_KEY=SG.your_api_key_here
```

### Production with AWS SES
```bash
EMAIL_FROM=noreply@yourcompany.com
AWS_ACCESS_KEY_ID=AKIA123456789
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-west-2
```

### Development with Mailpit (Local SMTP Server)
```bash
# Mailpit is just an SMTP server - use SMTP mode
EMAILER_MODE=smtp
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_TLS=false
# IMPORTANT: Do NOT set SMTP_USERNAME or SMTP_PASSWORD
# Mailpit does not support authentication
```

### Development with Mailtrap
```bash
EMAILER_MODE=smtp
SMTP_HOST=smtp.mailtrap.io
SMTP_PORT=2525
SMTP_USERNAME=your_username
SMTP_PASSWORD=your_password
SMTP_TLS=true
```

## Error Handling

- Configuration errors fallback to the `logger` provider
- Delivery failures are logged but don't crash the application in production
- In development, delivery failures raise exceptions for debugging

## Adding New Providers

To add a new email provider:

1. Create a new class inheriting from `Auth::Config::Email::Delivery::Base`
2. Implement the `deliver(email)` method
3. Override `validate_config!` for provider-specific validation
4. Add the provider to the `create_delivery_strategy` method in `Configuration`

Example:
```ruby
class CustomProvider < Base
  def deliver(email)
    # Implementation here
  end

  protected

  def validate_config!
    # Validation here
  end
end
```
