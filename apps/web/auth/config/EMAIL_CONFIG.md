# Email Configuration

The Auth application uses a flexible email delivery system that supports multiple providers and deployment scenarios.

## Configuration

Email delivery is configured via environment variables. The system will auto-detect the appropriate provider based on available configuration, or you can explicitly set the provider.

### Core Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `EMAIL_PROVIDER` | Force a specific provider (`smtp`, `sendgrid`, `ses`, `mailpit`, `logger`) | Auto-detected |
| `EMAIL_FROM` | Default sender email address | `noreply@onetimesecret.com` |
| `EMAIL_SUBJECT_PREFIX` | Prefix for all email subjects | `[OneTimeSecret] ` |
| `EMAIL_DELIVERY_MODE` | Delivery mode (`sync`, `async`, `test`) | `sync` |

### Provider-Specific Settings

#### SMTP (Generic)
```bash
EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=user@example.com
SMTP_PASSWORD=password123
SMTP_TLS=true  # Use TLS (default: true)
```

#### SendGrid
```bash
EMAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=SG.abc123...
```

#### AWS SES
```bash
EMAIL_PROVIDER=ses
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=abc123...
AWS_REGION=us-east-1
```

#### Mailpit (Development)
```bash
EMAIL_PROVIDER=mailpit
MAILPIT_HOST=localhost  # default: localhost
MAILPIT_PORT=1025      # default: 1025
```

#### Logger (Testing/Development)
```bash
EMAIL_PROVIDER=logger
# No additional configuration needed
```

## Auto-Detection Logic

When `EMAIL_PROVIDER` is not set, the system detects the provider in this order:

1. **Test Environment**: Uses `logger`
2. **SendGrid**: If `SENDGRID_API_KEY` is present
3. **AWS SES**: If `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are present
4. **Mailpit**: If `MAILPIT_HOST` or `MAILPIT_PORT` are set
5. **SMTP**: If `SMTP_HOST` is present
6. **Fallback**: Uses `logger`

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

### Development with Mailpit
```bash
MAILPIT_HOST=localhost
MAILPIT_PORT=1025
```

### Development with External SMTP
```bash
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
