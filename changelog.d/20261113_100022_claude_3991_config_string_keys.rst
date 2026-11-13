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
