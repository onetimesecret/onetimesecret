# Onetime Secret - Email Templates

## Templates

We use Rhales Single File Component templates, indicated by the .rue file extension.

### Password Request


The following handlebars tags are used in the template:

1. `{{baseuri}}` - Base URL of the website
2. `{{forgot_path}}` - Path to the password reset page
3. `{{email_address}}` - Recipient's email address

```
We received a request to reset your password for Onetime Secret

{{baseuri}}{{forgot_path}}

Delano
{{baseuri}}

P.S. This email was sent to {{email_address}}. If you did not make this request, you can safely ignore it.
```


### Secret Link

The following handlebars tags are used in the template:

1. `{{ i18n.email.body1 }}` - Internationalized text for the first part of the email body
2. `{{ custid }}` - Customer ID or username
3. `{{ display_domain }}` - The domain part of the secret link
4. `{{ uri_path }}` - The path portion of the secret link URL
5. `{{ i18n.email.body_tagline }}` - Internationalized text for the email tagline
6. `{{ baseuri }}` - Base URI of the website

```
{{ i18n.email.body1 }} {{ custid }}:

{{ display_domain }}{{ uri_path }}

{{ i18n.email.body_tagline }}
{{ baseuri }}/feedback
```

### Feedback

The following handlebars tags are used in the template:

1. `{{message}}` - The main email message content
2. `{{baseuri}}` - Base URL of the website, used twice (once as link text and once as href)


```
{{message}}

Secret Support
{{baseuri}}
```

### Incoming Support

1. `{{i18n.email.body1}}` - First part of the body text
2. `{{from}}` - Sender information
3. `{{baseuri}}` - Base URL
4. `{{verify_uri}}` - Verification URI path


```
{{i18n.email.body1}} {{from}}:

{{baseuri}}{{verify_uri}}
```


### Test Email

The following handlebars tags are used in the template:

1. `{{test_variable}}` - A test variable value
2. `{{baseuri}}` - Base URL of the application
3. `{{verify_uri}}` - URI path for verification
4. `{{i18n.email.postscript1}}` - First part of internationalized postscript text
5. `{{email_address}}` - User's email address
6. `{{i18n.email.postscript2}}` - Second part of internationalized postscript text

```
This email is a test from Onetime Secret!

This is a test variable: {{test_variable}}

{{baseuri}}{{verify_uri}}

Secret Support
{{baseuri}}

P.S.{{i18n.email.postscript1}}{{email_address}}.{{i18n.email.postscript2}}
```


### Welcome

1. `{{i18n.email.body1}}` - Internationalized greeting/introduction text
2. `{{i18n.email.please_verify}}` - Internationalized verification request message
3. `{{baseuri}}` - Base URL of the website
4. `{{verify_uri}}` - Verification URI/path for account verification
5. `{{i18n.email.postscript1}}` - First part of internationalized postscript
6. `{{email_address}}` - User's email address
7. `{{i18n.email.postscript2}}` - Second part of internationalized postscript


```
{{i18n.email.body1}}

{{i18n.email.please_verify}}

{{baseuri}}{{verify_uri}}

Delano
{{baseuri}}

P.S. {{i18n.email.postscript1}} {{email_address}}. {{i18n.email.postscript2}}
```
