Fixed
-----

- Fixed customer purges stopping after organization deletion when legacy
  membership references remained. Organization deletion now removes those
  references. Retrying an earlier partial purge automatically removes verified
  stale references without a separate customer-doctor repair; remaining dependent
  data still blocks deletion.
