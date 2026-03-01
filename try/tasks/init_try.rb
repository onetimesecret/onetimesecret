# try/tasks/init_try.rb
#
# frozen_string_literal: true

# Unit tests for OTSInit.read_env and OTSInit.write_env helpers
# defined in lib/tasks/init.rake.

require 'tmpdir'
require 'set'
require 'rake'
load File.expand_path('../../lib/tasks/init.rake', __dir__)

@tmpdir = Dir.mktmpdir('ots_init_try')
@env_path = File.join(@tmpdir, '.env')

## read_env: returns empty hash for empty file
File.write(@env_path, "")
OTSInit.read_env(@env_path)
#=> {}

## read_env: skips comment lines
File.write(@env_path, "# this is a comment\nKEY=value\n")
OTSInit.read_env(@env_path)
#=> { 'KEY' => 'value' }

## read_env: skips blank lines
File.write(@env_path, "\n\nFOO=bar\n\nBAZ=qux\n")
OTSInit.read_env(@env_path)
#=> { 'FOO' => 'bar', 'BAZ' => 'qux' }

## read_env: handles = signs in value
File.write(@env_path, "DB_URL=postgres://host/db?opt=1&x=2\n")
OTSInit.read_env(@env_path)
#=> { 'DB_URL' => 'postgres://host/db?opt=1&x=2' }

## read_env: strips surrounding double quotes from value
File.write(@env_path, "SECRET=\"mysecret\"\n")
OTSInit.read_env(@env_path)
#=> { 'SECRET' => 'mysecret' }

## read_env: strips surrounding single quotes from value
File.write(@env_path, "SECRET='mysecret'\n")
OTSInit.read_env(@env_path)
#=> { 'SECRET' => 'mysecret' }

## read_env: returns empty hash for nonexistent file
OTSInit.read_env(File.join(@tmpdir, 'nope'))
#=> {}

## write_env: updates an existing key
File.write(@env_path, "A=old\nB=keep\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, { 'A' => 'new' })
File.read(@env_path)
#=> "A=new\nB=keep\n"

## write_env: uncomments a placeholder line
File.write(@env_path, "# comment\n#SESSION_SECRET=\nOTHER=val\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, { 'SESSION_SECRET' => 'derived123' })
File.read(@env_path)
#=> "# comment\nSESSION_SECRET=derived123\nOTHER=val\n"

## write_env: appends key not found in existing lines
File.write(@env_path, "EXISTING=yes\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, { 'NEW_KEY' => 'added' })
File.read(@env_path)
#=> "EXISTING=yes\nNEW_KEY=added\n"

## write_env: preserves lines not in updates
File.write(@env_path, "KEEP=me\nALSO=here\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, {})
File.read(@env_path)
#=> "KEEP=me\nALSO=here\n"

## write_env: block markers are NOT treated as placeholders
File.write(@env_path, "#-----BEGIN DERIVED SECRETS-----\n#SESSION_SECRET=\n#-----END DERIVED SECRETS-----\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, { 'SESSION_SECRET' => 'abc' })
result = File.read(@env_path)
result.include?('#-----BEGIN DERIVED SECRETS-----')
#=> true

## write_env: block marker end line is also preserved
File.write(@env_path, "#-----BEGIN DERIVED SECRETS-----\n#SESSION_SECRET=\n#-----END DERIVED SECRETS-----\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, { 'SESSION_SECRET' => 'abc' })
result = File.read(@env_path)
result.include?('#-----END DERIVED SECRETS-----')
#=> true

## write_env: blank lines are preserved
File.write(@env_path, "A=1\n\nB=2\n")
lines = File.readlines(@env_path, chomp: true)
OTSInit.write_env(@env_path, lines, { 'A' => 'updated' })
File.read(@env_path).count("\n")
#=> 3

require 'fileutils'
FileUtils.rm_rf(@tmpdir)
