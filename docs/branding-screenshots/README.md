# Branding verification screenshots

Visual confirmation for the branding-polish branch, captured against the real
running app (Ruby backend + the built frontend) with seeded custom domains.

These are **verification artifacts** for PR review and can be removed before
merge.

| File | What it shows |
|---|---|
| `01-disabled-homepage-keyhole-dark.png` | Disabled homepage, unbranded (dark). The neutral **keyhole** now renders where the OTS maruhi (秘) used to — same screen as the original bug report. |
| `02-custom-domain-with-uploaded-logo.png` | Disabled homepage on a custom domain with an uploaded logo → the **tenant's logo** displays. |
| `03-custom-domain-branded-monogram.png` | Disabled homepage on a branded custom domain with no logo → **monogram** in the brand color. |
| `04-disabled-homepage-minimal-keyhole.png` | The `minimal` variant, unbranded → neutral **keyhole**. |

Centred-mark priority (verified): configured custom-domain logo → branded
monogram → neutral keyhole. The maruhi no longer appears in any neutral context.
