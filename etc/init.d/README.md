# System initialization scripts that run during boot for each
# configuration section (following Unix /etc/init.d convention)

Each Ruby script corresponds to a top-level configuration section (e.g., site.rb for
the 'site' config). Scripts execute during the config processing phase with access to:
- `config` - the full configuration hash (still mutable)
- `section_config` - the specific section being initialized
- Boot-time options (mode, instance, etc.)

These scripts handle section-specific setup: modifying config, registering routes,
setting feature flags. They run BEFORE config is frozen, unlike onetime/initializers
which configure system-wide services (Redis, databases, etc.) using frozen config.

Scripts are optional - only sections with corresponding .rb files are initialized.
