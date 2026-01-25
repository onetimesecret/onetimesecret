Added
-----

- New unified session architecture using standard Onetime::Session store
- Authentication adapter pattern supporting both Redis-backed auth and future Rodauth integration
- Session helpers extracted to dedicated modules for cleaner controller code
- CSRF protection via shrimp tokens now integrated with Rack sessions

Changed
-------

- Controllers now use env['onetime.session'] instead of custom Onetime::Session model
- Identity resolution middleware updated to read from standard Rack sessions
- Session persistence moved from custom Familia model to Rack::Session standard
- Colonel stats tracking simplified with session counting removed (handled by middleware)

Removed
-------

- V2::Session model and all associated custom session management code
- SessionMessages mixin (functionality moved to standard session handling)
- ClearSessionMessages middleware (no longer needed with Rack::Session)
- Custom session-based tryout tests replaced with Rack::Session approach
- Deprecated customer session management methods

AI Assistance
-------------

- Session architecture implementation guided by Claude Code per issue #1673
