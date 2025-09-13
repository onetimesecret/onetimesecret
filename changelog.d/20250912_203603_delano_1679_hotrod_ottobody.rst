.. Integrate Otto authentication service with unified Redis session management

Changed
-------

- Integrated Otto customer creation with Rodauth account registration, automatically linking new accounts with derived Otto external IDs
- Unified session management by replacing Roda sessions with Redis-backed Rack::Session::RedisFamilia for consistency across applications
- Enhanced session validation with Otto integration checks and configurable session expiration
- Updated session cookie configuration for unified naming convention (ots.session, ots.remember)

Added
-----

- Database migration 002_add_external_id.rb to support Otto's derived identity integration with unique indexing
- Redis session compatibility methods for validating Otto-linked authentication state

Removed
-------

- NewRelic monitoring dependency from auth service production Gemfile (moved to application-level configuration)
