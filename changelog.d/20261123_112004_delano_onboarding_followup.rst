Security
--------

- Diagnostic bundles now refuse shared output directories and avoid replacing
  existing archive paths. Failed archives are removed before reporting an error.
- The Docker quick start creates credential files privately, preserves them on
  repeat use, and refuses linked files and unsafe working directories.
..
