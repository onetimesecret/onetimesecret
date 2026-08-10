# docs/specs/custom-mail-sender/custom-mail-sender-smtp2go-addendum.md

---

Validation of the SMTP2GO API Integration Guide against the official documentation:

| Claim                                                                                                                                                                | Status     | Notes                                      |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------ |
| RESTful HTTP API, JSON in/out                                                                                                                                        | ✅ Correct | Confirmed                                  |
| Authentication via `api_key` field or `X-Smtp2go-Api-Key` header                                                                                                     | ✅ Correct | Confirmed                                  |
| API keys managed under **Sending > API Keys**                                                                                                                        | ✅ Correct | Confirmed                                  |
| API keys are 32 characters                                                                                                                                           | ✅ Correct | Confirmed                                  |
| Base URL `https://api.smtp2go.com/v3/`                                                                                                                               | ✅ Correct | Confirmed via multiple endpoint references |
| `Content-Type: application/json`                                                                                                                                     | ✅ Correct | Confirmed                                  |
| `200 OK` = success                                                                                                                                                   | ✅ Correct | Confirmed                                  |
| `401` for invalid/missing API key                                                                                                                                    | ✅ Correct | Confirmed                                  |
| Max email size 50 MB                                                                                                                                                 | ✅ Correct | Confirmed                                  |
| Max 100 recipients per To/CC/BCC field                                                                                                                               | ✅ Correct | Confirmed                                  |
| Each recipient counts as one email                                                                                                                                   | ✅ Correct | Confirmed                                  |
| Subaccount support via `subaccount_id`                                                                                                                               | ✅ Correct | Confirmed                                  |
| `/v3/email/send` and `/v3/email/mime` endpoints                                                                                                                      | ✅ Correct | Confirmed                                  |
| `sender`, `to`, `subject`, `html_body`, `text_body`, `attachments`, `inlines`, `custom_headers`, `template_id`, `template_data`, `schedule`, `fastaccept` parameters | ✅ Correct | Confirmed                                  |
| `subject`/`html_body`/`text_body` ignored if `template_id` passed                                                                                                    | ✅ Correct | Confirmed                                  |
| `custom_headers` disallow `Content-Type`, `Content-Transfer-Encoding`, `MIME-Version`                                                                                | ✅ Correct | Confirmed                                  |
| `schedule` must be future and within 3 days; returns `schedule_id`; max 50,000 queued                                                                                | ✅ Correct | Confirmed                                  |
| `fastaccept` recommended, will become default                                                                                                                        | ✅ Correct | Confirmed                                  |
| Sender verification mandatory; unverified senders rejected                                                                                                           | ✅ Correct | Confirmed                                  |
| Sender domain vs single sender email verification options                                                                                                            | ✅ Correct | Confirmed                                  |
| `/v3/domain/add` requires `domain`, `tracking_subdomain`, `returnpath_subdomain`                                                                                     | ✅ Correct | Confirmed                                  |
| `/v3/domain/verify` requires `domain`, `ssl_certificate` defaults true, `subaccount_id` optional                                                                     | ✅ Correct | Confirmed                                  |
| Verification removes need to wait for 7-minute periodic check                                                                                                        | ✅ Correct | Confirmed                                  |

Issues found:

1. **Response codes table**: The guide lists only `200`, `400`, `401`. The official docs also include `402`, `403`, `404`, `429`, and `500`/`502`/`503`/`504` [^2]. The guide should mention these for completeness.

2. **Domain add response**: The guide states SMTP2GO provides "three CNAME records" after `/v3/domain/add`. The documentation confirms DNS records are required, but the librarian could not retrieve the exact response schema from the reference page. The dashboard guide likely provides the CNAME details; the API response may or may not include them directly. This is plausible but not fully verified from the API reference.

3. **"validate email domains" framing**: The user's original question asked about validating email _domains_. SMTP2GO's domain verification is for sender authorization (proving domain ownership), not for validating whether arbitrary recipient domains are reachable. The guide correctly focuses on sender domain verification, but the terminology could be clearer that this is _sender_ domain verification, not recipient domain validation.

4. **No mention of `402`/`403`/`404`/`429`/server errors**: Should be added to the error handling section.

5. **No mention of click tracking requirements**: The docs note that to track URL clicks you must enable click tracking for the API key, use full anchor HTML elements, and include `https://` in the HREF [^1]. This is optional but worth noting.

6. **No mention of `template_data` for custom subject**: The docs note you can set a custom subject via template variables [^1]. The guide mentions `template_data` but not this subject detail.

Overall: the guide is **substantially accurate**. The main gaps are the incomplete response-code list and the slight ambiguity around "domain validation" vs "sender domain verification."

**References**

[^1]: [Send a standard email](https://developers.smtp2go.com/reference/send-standard-email) (67%)

[^2]: [Response Codes](https://developers.smtp2go.com/docs/response-codes) (33%)
