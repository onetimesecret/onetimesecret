Security
--------

- Refuse encrypted secret creation and email-change requests when the stored
  key verifier differs from the running ``SECRET``. A verifier check that was
  unavailable at startup is retried before the next encrypted write.
- Rotating ``SECRET`` now retires API bearer tokens signed with the old key,
  even if ``SECRET_PREVIOUS`` retains that key for ciphertext decryption.
  Clients must obtain new bearer tokens after rotation.
