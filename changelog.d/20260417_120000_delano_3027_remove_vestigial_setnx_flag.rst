.. A new scriv changelog fragment.

Removed
-------

- Dropped the vestigial ``ots:migration_needed:db_0`` SETNX write from the connection pool initializer. The flag was never read and its name misled operators grepping Redis — actual migrations run through ``bin/ots migrate`` and ``Familia::Migration::Base``, which are independent of this key. Removes one Redis round-trip per boot. (#3027)
