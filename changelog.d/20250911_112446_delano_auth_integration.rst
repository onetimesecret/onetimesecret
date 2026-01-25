Fixed
-----

- Auth service now properly loads Vite assets in both development and production modes, eliminating style flash and Vue app initialization errors
- Development mode loads scripts from Vite dev server with proper URL configuration for hot module replacement
- Production mode uses compiled manifest with optimized asset loading and font preloading
- Removed duplicate window.__ONETIME_STATE__ initialization that was causing conflicts
- Fixed hardcoded frontend_development flag to use dynamic configuration
- Improved script placement consistency with core app (all assets loaded in head section)
- Added critical CSS to prevent flash of unstyled content during asset loading
- Enhanced ViteAssets helper with proper dev server URL support and configuration awareness
