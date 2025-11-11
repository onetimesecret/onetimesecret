# Caddy Security UI Customization

Custom branding for the Caddy Security authentication portal to match OneTimeSecret's visual identity.

## Files

- **custom.css** - Custom CSS with OneTimeSecret brand colors and Zilla Slab font
- **head.html** - Logo/header HTML injected into `<head>` section

## Brand Colors

From `tailwind.config.ts`:

- **Primary**: `#dc4a22` (orange)
- **Hover**: `#c43d1b` (darker orange)
- **Accent**: `#23b5dd` (blue)
- **Light**: `#f7dec3` (peach)
- **Dark**: `#a32d12` (deep orange)

## Font

**Zilla Slab** (serif) - loaded from main site at `/assets/fonts/zs/`

## Usage

Referenced in `etc/Caddyfile`:

```caddyfile
authentication portal myportal {
  ui {
    custom css path /Users/d/Projects/opensource/onetime/onetimesecret/etc/caddy-ui/custom.css
    custom html header path /Users/d/Projects/opensource/onetime/onetimesecret/etc/caddy-ui/head.html
  }
}
```

## Testing

1. Reload Caddy:
   ```bash
   caddy reload --config etc/Caddyfile
   ```

2. Visit auth portal:
   ```bash
   open https://dev.onetime.dev/auth/portal
   ```

3. Check branding:
   - Orange buttons (#dc4a22)
   - Blue links (#23b5dd)
   - Zilla Slab font
   - "Onetime Secret" header/logo

## Customization

Edit `custom.css` for styling changes. Edit `head.html` for logo/header changes.

Changes take effect after `caddy reload`.

## Production Deployment

For production, consider:

1. **Option A**: Keep in repo, update paths in production Caddyfile
2. **Option B**: Copy to `~/.local/caddy/ui/` and use `{env.HOME}` variable
3. **Option C**: Create custom theme in go-authcrunch (requires rebuild)

## References

- [Caddy Security UI Docs](https://github.com/greenpau/go-authcrunch/blob/main/docs/authenticate/55-ui-features.md)
- [Basic Theme Templates](https://github.com/greenpau/go-authcrunch/tree/main/assets/portal/templates/basic)
