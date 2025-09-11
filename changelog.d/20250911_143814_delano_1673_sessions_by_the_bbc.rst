Added
-----

- New unified session architecture using standard Rack::Session::RedisFamilia store
- Authentication adapter pattern supporting both Redis-backed auth and future Rodauth integration
- Session helpers extracted to dedicated modules for cleaner controller code
- CSRF protection via shrimp tokens now integrated with Rack sessions

Changed
-------

- Controllers now use env['rack.session'] instead of custom V2::Session model
- Identity resolution middleware updated to read from standard Rack sessions
- Session persistence moved from custom Familia model to Rack::Session standard

AI Assistance
-------------

- Session architecture implementation guided by Claude Code per issue #1673
