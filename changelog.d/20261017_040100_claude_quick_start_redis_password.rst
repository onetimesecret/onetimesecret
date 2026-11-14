.. A new scriv changelog fragment.

Security
--------

- The README Docker quick start no longer publishes Redis on every host
  interface without a password. The recipe now runs Redis on a private
  Docker network with ``--requirepass`` and passes the password in
  ``REDIS_URL``; the Dockerfile header and the ``docker-run-readme`` CI job
  follow it, and a unit guard fails if the README drifts back. Installs made
  from the old recipe should restart Redis with ``--requirepass`` and without
  ``-p 6379:6379``, put the password in ``REDIS_URL``, and treat secrets and
  sessions held while the port was open as possibly read. The
  ``docker/README.md`` debugging section no longer claims the simple compose
  stack publishes Valkey on loopback; it uses ``expose`` only.
