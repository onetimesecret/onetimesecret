Fixed
-----

- Auth service now properly loads Vite assets in both development and production modes, eliminating style flash and Vue app initialization errors
- Development mode loads scripts in head section for proper hot module replacement
- Production mode uses compiled manifest with optimized asset loading and font preloading
- Added critical CSS to prevent flash of unstyled content during asset loading
