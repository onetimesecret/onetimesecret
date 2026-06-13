.. A new scriv changelog fragment.

Security
--------

- Generated secrets and passwords are now fully derived from a CSPRNG. The
  complexity path of ``Onetime::Utils.strand`` (taken whenever more than one
  character class is enabled, which is the default for generated secrets) used
  ``Array#sample`` to pick the guaranteed character from each class and
  ``Array#shuffle`` to order the final string. Both draw from Ruby's default
  ``Random`` (a non-cryptographic Mersenne Twister), so those positions and the
  overall ordering were predictable from the PRNG state despite the method's
  documented cryptographic guarantee. They now use ``SecureRandom`` via new
  ``secure_sample`` / ``secure_shuffle`` helpers, matching the bulk-fill path
  that was already secure.
