.. Phase 2: Complete identity resolution middleware for Otto/Rodauth integration

Added
-----

- Identity resolution middleware integrated across all applications (API v1, v2, Web Core)
- Dual authentication mode support (basic Redis vs Rodauth) with automatic detection
- External ID lookup functionality in Onetime::Customer for Otto-Rodauth identity bridging
- RodauthUser class for unified user representation with full feature access

Changed
-------

- Identity resolution middleware now supports both Redis-only and Rodauth authentication modes
- All application middleware stacks updated to include centralized identity resolution
- Customer lookup enhanced with find_by_extid method for external identity resolution
- Authentication flow unified across applications with consistent user object interfaces
