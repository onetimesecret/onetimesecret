.. A new scriv changelog fragment.

Added
-----

- Git JSON merge driver for automated locale file conflict resolution. Semantic 3-way merging automatically resolves non-conflicting changes in ``src/locales/**/*.json`` files, preserving keys added on different branches without manual conflict resolution.
- ``.gitattributes`` configuration for locale JSON files to enable the custom merge driver.

Documentation
-------------

- Added Git JSON merge driver setup instructions to README.md Development section.
