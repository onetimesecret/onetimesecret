Fixed
-----

- HTTP request logs, including the debug-mode request trace, redact secret and
  receipt capability paths in every capture mode. Burn, email-delivery and receipt lifecycle logs use short identifiers;
  receipt-list errors omit raw exception messages. Reverse-proxy and other
  external access logs require their own redaction configuration.
