.. A new scriv changelog fragment.

Changed
-------

- ``Rack::DetectHost`` now treats a present ``otto.via_trusted_proxy`` env
  key as authoritative in both directions, consuming otto's tri-state
  contract (delano/otto#228): otto writes the key only when proxy trust is
  actually configured, so ``true`` grants forwarded-host trust, ``false``
  (or any non-boolean) denies it — a request resolving to a private
  ``REMOTE_ADDR`` can no longer bypass an operator's explicit trust
  decision. The legacy private-IP heuristic now applies only when the key
  is absent (no proxy trust configured, or no ``IPPrivacyMiddleware``
  mounted), which keeps default-config self-hosted installs behind a local
  reverse proxy working unchanged. The middleware's key constant now
  references ``Otto::EnvKeys::VIA_TRUSTED_PROXY`` directly, leaving one
  rename surface instead of two duplicated literals. (#4024)
