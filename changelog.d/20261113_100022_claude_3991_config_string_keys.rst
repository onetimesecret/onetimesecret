.. A new scriv changelog fragment.

Changed
-------

- Config keys are Strings on every load path. A key written as a Symbol in a
  config file (``:host:``) is read as ``host``; before, it was converted when
  ``etc/defaults/config.defaults.yaml`` was layered under the file and ignored
  when the file was loaded alone. A key set twice on one level, once as a
  Symbol and once as a String (``:host:`` and ``host:``), now stops boot with
  a ``ConfigError`` that names the key; before, one of the two values took
  effect and the other was ignored without a message. Symbol values (``default_validation_type:
  :regex``) are unchanged. (#3991)
