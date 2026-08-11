# docs/specs/custom-mail-sender/custom-mail-sender-smtp2go.md

---

# SMTP2GO API Integration Guide

## Overview

The SMTP2GO API is a RESTful HTTP API that lets you programmatically send emails/SMS, manage account features, and verify sender domains. All input and output is JSON, and every request requires authentication via an API key [^2].

---

## Authentication

Every API call must include an API key. Keys are managed under **Sending > API Keys** in the SMTP2GO dashboard and are formatted as `api-` followed by 32 characters [^1].

Two ways to authenticate:

| Method                   | How                                                          |
| ------------------------ | ------------------------------------------------------------ |
| **Header** (recommended) | `X-Smtp2go-Api-Key: api-xxxxxxxxxxxxxxxxxx`                  |
| **JSON body**            | `"api_key": "api-xxxxxxxxxxxxxxxxxx"` in the request payload |

Missing or invalid keys return `401 Unauthorized` [^1].

### Key technical details

- **Base URL**: `https://api.smtp2go.com/v3/`
- **Content-Type**: `application/json`
- **Accept**: `application/json`
- All responses are JSON; `200 OK` indicates success [^1]
- Max email size: **50 MB** (content + attachments + headers) [^9]
- Max recipients: **100 per field** (To, CC, BCC each). Each recipient counts as one email from your quota [^1]
- Subaccount support via `subaccount_id` parameter [^1]

---

## 1. Sending Emails

There are two endpoints for sending:

| Endpoint              | Use case                                                            |
| --------------------- | ------------------------------------------------------------------- |
| `POST /v3/email/send` | **Standard email** — pass JSON components (sender, body, recipient) |
| `POST /v3/email/mime` | **MIME email** — pass a pre-built raw MIME message                  |

### `/email/send` — Request Parameters

| Parameter        | Type             | Required             | Description                                                                                               |
| ---------------- | ---------------- | -------------------- | --------------------------------------------------------------------------------------------------------- |
| `sender`         | string           | Yes                  | From address, format: `Name <user@domain.com>`                                                            |
| `to`             | array of strings | Yes                  | Up to 100 recipients, format: `Name <user@domain.com>`                                                    |
| `cc`             | array of strings | No                   | Up to 100 CC recipients                                                                                   |
| `bcc`            | array of strings | No                   | Up to 100 BCC recipients                                                                                  |
| `subject`        | string           | No\*                 | Email subject (ignored if `template_id` is set)                                                           |
| `html_body`      | string           | No\*                 | HTML body (required if no `template_id` and no `text_body`)                                               |
| `text_body`      | string           | No\*                 | Plain text body (required if no `template_id` and no `html_body`)                                         |
| `custom_headers` | array of objects | No                   | Custom headers (e.g. `Reply-To`). `Content-Type`, `Content-Transfer-Encoding`, `MIME-Version` not allowed |
| `attachments`    | array of objects | No                   | File attachments                                                                                          |
| `inlines`        | array of objects | No                   | Inline images (use `cid:filename` in HTML)                                                                |
| `template_id`    | string           | No                   | ID of a pre-created template                                                                              |
| `template_data`  | JSON             | No                   | Variable values for template: `{"var1": "value1"}`                                                        |
| `schedule`       | string           | No                   | Timestamp to schedule sending (within next 3 days). Returns `schedule_id`                                 |
| `fastaccept`     | boolean          | No (default `false`) | If `true`, email is accepted immediately and sent in background. **Recommended** — will become default    |

[^3][^7]

### cURL Example — Send Email

```bash
curl --request POST \
     --url https://api.smtp2go.com/v3/email/send \
     --header 'Content-Type: application/json' \
     --header 'X-Smtp2go-Api-Key: api-xxxxxxxxxxxxxxxxxx' \
     --header 'accept: application/json' \
     --data '
{
  "sender": "sender@example.com",
  "to": [
    "recipient@example.com"
  ],
  "subject": "My First Email",
  "text_body": "Hello from the other side."
}
'
```

[^7]

### Python Example — Send Email

```python
import requests

url = "https://api.smtp2go.com/v3/email/send"
headers = {
    "Content-Type": "application/json",
    "X-Smtp2go-Api-Key": "api-xxxxxxxxxxxxxxxxxx",
    "accept": "application/json"
}
payload = {
    "sender": "sender@example.com",
    "to": ["recipient@example.com"],
    "subject": "Hello from SMTP2GO",
    "html_body": "<h1>Welcome!</h1><p>This is a test email.</p>",
    "text_body": "Welcome! This is a test email.",
    "fastaccept": True
}

response = requests.post(url, json=payload, headers=headers)
print(response.json())
```

### Success Response (200 OK)

```json
{
  "request_id": "aa253464-0bd0-467a-b24b-6159dcd7be60",
  "data": {
    "succeeded": 1,
    "failed": 0,
    "failures": [],
    "email_id": "1er8bV-6Tw0Mi-7h"
  }
}
```

### Error Response (400)

```json
{
  "request_id": "22e5acba-43bf-11e6-ae42-408d5cce2644",
  "data": {
    "error_code": "E_ApiResponseCodes.ENDPOINT_PERMISSION_DENIED",
    "error": "You do not have permission to access this API endpoint"
  }
}
```

[^7]

### Python Example — Send with Attachments and Custom Headers

```python
import requests
import base64

with open("report.pdf", "rb") as f:
    attachment_b64 = base64.b64encode(f.read()).decode("utf-8")

payload = {
    "sender": "sender@example.com",
    "to": ["recipient@example.com"],
    "subject": "Monthly Report",
    "html_body": "<p>Please find the report attached.</p>",
    "text_body": "Please find the report attached.",
    "custom_headers": [
        {"header": "Reply-To", "value": "reply@example.com"}
    ],
    "attachments": [
        {
            "filename": "report.pdf",
            "fileblob": attachment_b64,
            "mimetype": "application/pdf"
        }
    ],
    "fastaccept": True
}

response = requests.post(
    "https://api.smtp2go.com/v3/email/send",
    json=payload,
    headers={
        "Content-Type": "application/json",
        "X-Smtp2go-Api-Key": "api-xxxxxxxxxxxxxxxxxx"
    }
)
print(response.json())
```

---

## 2. Validating / Verifying Email Domains

**Sending from a verified sender is mandatory** — attempts to send from an unverified sender will be rejected [^1].

There are two verification paths:

| Method                  | How it works                                                                                                     | Recommended for                    |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| **Sender Domain**       | Add domain, then add 3 CNAME DNS records (SPF, DKIM, tracking). Allows sending from _any_ address at that domain | SPF/DKIM alignment, production use |
| **Single Sender Email** | Add a specific email address; SMTP2GO sends a verification link email that must be clicked                       | When you can't edit DNS            |

[^4]

### Step 1: Add a Sender Domain

**Endpoint**: `POST https://api.smtp2go.com/v3/domain/add`

| Parameter              | Type   | Required | Description                                       |
| ---------------------- | ------ | -------- | ------------------------------------------------- |
| `domain`               | string | Yes      | Domain to add (you must own it)                   |
| `tracking_subdomain`   | string | Yes      | Subdomain for tracking (e.g. `track`)             |
| `returnpath_subdomain` | string | Yes      | Subdomain for return path/bounces (e.g. `bounce`) |
| `subaccount_id`        | string | No       | Subaccount ID if acting on behalf of a subaccount |

> **Note:** The `tracking_subdomain` and `returnpath_subdomain` must be configured in the domain's DNS and propagated for verification to succeed [^6].

```bash
curl --request POST \
     --url https://api.smtp2go.com/v3/domain/add \
     --header 'Content-Type: application/json' \
     --header 'X-Smtp2go-Api-Key: api-xxxxxxxxxxxxxxxxxx' \
     --data '
{
  "domain": "example.com",
  "tracking_subdomain": "track",
  "returnpath_subdomain": "bounce"
}
'
```

After adding the domain, SMTP2GO provides **three CNAME records** to add to your DNS:

| Record  | Purpose                                |
| ------- | -------------------------------------- |
| CNAME 1 | SPF alignment                          |
| CNAME 2 | DKIM alignment                         |
| CNAME 3 | Tracking (opens, clicks, unsubscribes) |

[^4]

### Step 2: Verify the Sender Domain

Once DNS records are propagated, trigger verification via the API:

**Endpoint**: `POST https://api.smtp2go.com/v3/domain/verify`

| Parameter         | Type    | Required            | Description                                                          |
| ----------------- | ------- | ------------------- | -------------------------------------------------------------------- |
| `domain`          | string  | Yes                 | Domain to verify                                                     |
| `ssl_certificate` | boolean | No (default `true`) | Requisition an SSL certificate for the tracking domain once verified |
| `subaccount_id`   | string  | No                  | Subaccount ID if acting on behalf of a subaccount                    |

[^5]

```bash
curl --request POST \
     --url https://api.smtp2go.com/v3/domain/verify \
     --header 'Content-Type: application/json' \
     --header 'X-Smtp2go-Api-Key: api-xxxxxxxxxxxxxxxxxx' \
     --data '
{
  "domain": "example.com",
  "ssl_certificate": true
}
'
```

This removes the need to wait for SMTP2GO's automatic periodic verification (which runs every 7 minutes) [^5].

### Python Example — Full Domain Add + Verify Flow

```python
import requests
import time

API_KEY = "api-xxxxxxxxxxxxxxxxxx"
BASE_URL = "https://api.smtp2go.com/v3"
HEADERS = {
    "Content-Type": "application/json",
    "X-Smtp2go-Api-Key": API_KEY
}

# Step 1: Add the sender domain
add_response = requests.post(f"{BASE_URL}/domain/add", headers=HEADERS, json={
    "domain": "example.com",
    "tracking_subdomain": "track",
    "returnpath_subdomain": "bounce"
})
print("Add domain:", add_response.json())

# ... Add the 3 CNAME records to your DNS provider ...
# ... Wait for DNS propagation ...

# Step 2: Verify the domain (once DNS propagated)
verify_response = requests.post(f"{BASE_URL}/domain/verify", headers=HEADERS, json={
    "domain": "example.com",
    "ssl_certificate": True
})
print("Verify domain:", verify_response.json())
```

---

## 3. End-to-End Integration Summary

```
┌──────────────────────────────────────────────────────┐
│  1. Get API Key from SMTP2GO dashboard               │
│     (Sending > API Keys)                             │
├──────────────────────────────────────────────────────┤
│  2. Verify your sender domain                        │
│     a. POST /v3/domain/add                           │
│     b. Add 3 CNAME records to DNS (SPF/DKIM/Track)   │
│     c. POST /v3/domain/verify                        │
├──────────────────────────────────────────────────────┤
│  3. Send emails via POST /v3/email/send              │
│     - Authenticate with X-Smtp2go-Api-Key header     │
│     - Pass JSON body with sender, to, subject, body  │
│     - Set fastaccept: true for async sending         │
│     - Optionally use templates, attachments, etc.    │
├──────────────────────────────────────────────────────┤
│  4. Handle responses                                 │
│     - 200 OK: check data.succeeded / data.failed     │
│     - 400: check data.error_code / data.error        │
│     - 401: invalid/missing API key                   │
└──────────────────────────────────────────────────────┘
```

### Key takeaways

- **Store your API key in environment variables**, never in source control [^1]
- **Domain verification is mandatory** before sending — use the API or the dashboard to add/verify [^1]
- **Set `fastaccept: true`** — it's faster and will become the default [^3]
- **Use templates** (`template_id` + `template_data`) for personalized emails at scale [^8]
- **Scheduled sending** is supported up to 3 days in the future via the `schedule` parameter [^3]
- Full API reference: [developers.smtp2go.com](https://developers.smtp2go.com)

**References**

[^1]: [Getting Started with the API](https://developers.smtp2go.com/docs/getting-started) (37%)

[^2]: [SMTP2GO API Documentation](https://developers.smtp2go.com/docs/introduction-guide) (12%)

[^3]: [Send a standard email](https://developers.smtp2go.com/reference/send-standard-email) (12%)

[^4]: [Verified Senders: Sender Domain vs Single Sender Emails – SMTP2GO Support Support Desk](https://support.smtp2go.com/hc/en-gb/articles/9150216032537-Verified-Senders-Sender-Domain-vs-Single-Sender-Emails) (10%)

[^5]: [Verify a sender domain](https://developers.smtp2go.com/reference/verify-a-sender-domain) (10%)

[^6]: [Add a sender domain](https://developers.smtp2go.com/reference/add-sender-domain) (8%)

[^7]: [Send an Email](https://developers.smtp2go.com/docs/send-an-email) (5%)

[^8]: [Getting started with Templates](https://developers.smtp2go.com/docs/getting-started-with-templates) (4%)

[^9]: [General API Resources](https://developers.smtp2go.com/reference/general-api-resources) (3%)
