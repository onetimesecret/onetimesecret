.. Phase 3: Otto authentication strategy integration and account lifecycle

Added
-----

- Account closure with automatic Otto customer cleanup in Rodauth after_close_account hook
- Enhanced V2 authentication strategies to use identity resolution middleware across all strategy types

Changed
-------

- V2SessionStrategy updated to leverage pre-resolved identity from IdentityResolution middleware
- V2CombinedStrategy refactored to prioritize identity resolution over basic auth with intelligent fallback
- V2OptionalStrategy enhanced with identity-aware anonymous access and improved authentication flow
- V2ColonelStrategy updated to use identity resolution for admin privilege validation
- All authentication strategies now support both Rodauth and Redis session sources with unified metadata
