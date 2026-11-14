.. A new scriv changelog fragment.

Changed
-------

- Config keys are Strings on every load path. A key that is not a String in
  a config file (``:host:``, ``1:``, ``true:``) is read as its String form
  (``host``, ``1``, ``true``); before, a Symbol key was converted when
  ``etc/defaults/config.defaults.yaml`` was layered under the file and
  ignored when the file was loaded alone. Two keys on one level with the
  same String form (``:host:`` and ``host:``) now stop boot with a
  ``ConfigError`` that names the key; before, one of the two values took
  effect and the other was ignored without a message. ``bin/ots config
  validate`` applies the same rules. Symbol values (``default_validation_type:
  :regex``) are unchanged. (#3991)
- The app reads its config through one reader, ``OT.conf.get('site.host')``.
  A setting the app requires that is missing from the loaded config now
  raises an error naming the path (``Config path 'site.host' is not set``)
  where it is read; before, the read returned nil and the failure showed up
  later, or not at all. ``etc/defaults/config.defaults.yaml`` defines every
  required setting, so this only happens when that file is missing or an
  operator file is loaded on its own. A setting an operator file sets to
  nil, or a section it empties, still reads as unset. (#3991)
