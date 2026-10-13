.. A new scriv changelog fragment.

Fixed
-----

- A custom domain with a Unicode subdomain, such as ``bücher.example.com``,
  can now be added. Its TXT verification record name is shown and checked
  in A-label form (``_onetime-challenge-<id>.xn--bcher-kva.example.com``),
  with the Unicode spelling shown beside it. The domain keeps the spelling
  it was entered with. (#4780)
- Adding a domain nested more than ten labels deep, or one whose TXT record
  name would be longer than DNS allows, now returns the reason instead of a
  server error. (#4780)
