# lib/onetime/initializers/set_encoding.rb
#
# Set the default external encoding to UTF-8 for the application.
# This ensures that all file I/O operations default to UTF-8 encoding,
# preventing "invalid byte sequence in US-ASCII" errors when reading
# configuration files, locales, and other text resources.
#
# This must be loaded before any initializers that read files.

Encoding.default_external = 'UTF-8'
Encoding.default_internal = 'UTF-8'
