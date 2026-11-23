Changed
-------

- The README Docker command and simple Compose stack now publish port 3000
  only on loopback. For remote access, use the full stack with TLS or put a
  TLS reverse proxy in front of the local port.

Fixed
-----

- The Compose quick start restricts an existing regular ``.env`` file before
  adding generated credentials. It leaves linked env files untouched and
  refuses to add missing keys through them. Direct Compose commands now load
  the root env file for variable interpolation.
