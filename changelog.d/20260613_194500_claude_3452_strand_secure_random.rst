.. A new scriv changelog fragment.

Fixed
-----

- ``Onetime::Utils.strand`` now draws every character of a generated secret from ``SecureRandom``. The complexity branch (used by default when more than one character set is enabled) previously seeded the guaranteed one-per-set characters with ``Array#sample`` and produced the final ordering with ``Array#shuffle``, both of which fall back to Ruby's non-cryptographic Mersenne Twister PRNG. Generated passwords are now fully CSPRNG-backed; there is no change to length, character sets, or the one-char-per-set guarantee. (#3452)
