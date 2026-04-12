# try/scripts/update_file_headers_try.rb
#
# frozen_string_literal: true

# Tests for scripts/update-file-headers.rb --fix mode.
#
# The script hardcodes REPO_ROOT via __dir__ and calls exit, so we shell out
# to it from an isolated tempdir. Fixtures are staged under the tempdir, the
# script is copied into <tempdir>/scripts/ so its REPO_ROOT resolves there,
# and we invoke it with --fix <relative_path> for each case.
#
# Verifies post-fix behavior for PR #2953 follow-ups: positional header
# detection (Ruby + Python) preserves license stubs, rubocop directives,
# encoding cookies, magic comments, and docstrings.

require 'tmpdir'
require 'fileutils'
require 'open3'
require 'pathname'

SCRIPT_SRC = File.expand_path('../../scripts/update-file-headers.rb', __dir__)

# Stage the script into a temp "repo" so REPO_ROOT = tmpdir.
# Returns [tmpdir_path, script_path_in_tmpdir].
def stage_repo
  tmp = Dir.mktmpdir('uhdr_')
  FileUtils.mkdir_p(File.join(tmp, 'scripts'))
  script = File.join(tmp, 'scripts', 'update-file-headers.rb')
  FileUtils.cp(SCRIPT_SRC, script)
  [tmp, script]
end

def run_fix(tmpdir, script, relative_path)
  Open3.capture3('ruby', script, '--fix', relative_path, chdir: tmpdir)
end

def run_check(tmpdir, script, relative_path)
  Open3.capture3('ruby', script, relative_path, chdir: tmpdir)
end

def write_file(tmpdir, relpath, content)
  full = File.join(tmpdir, relpath)
  FileUtils.mkdir_p(File.dirname(full))
  File.write(full, content)
  full
end

def read_file(tmpdir, relpath)
  File.read(File.join(tmpdir, relpath))
end

## Ruby file with frozen_string_literal magic comment is left intact
@tmp, @script = stage_repo
write_file(@tmp, 'lib/example.rb', <<~RB)
  # lib/example.rb
  # frozen_string_literal: true

  class Example; end
RB
_, _, @status = run_fix(@tmp, @script, 'lib/example.rb')
@out = read_file(@tmp, 'lib/example.rb')
@out.include?('# frozen_string_literal: true') &&
  @out.include?('class Example; end') &&
  @out.start_with?("# lib/example.rb\n#\n# frozen_string_literal: true\n\n")
#=> true

## Ruby file with rubocop directives preserved
@tmp, @script = stage_repo
write_file(@tmp, 'lib/rubo.rb', <<~RB)
  # lib/rubo.rb
  # rubocop:disable Style/Documentation
  # rubocop:disable Metrics/ClassLength

  class Rubo; end
RB
run_fix(@tmp, @script, 'lib/rubo.rb')
@out = read_file(@tmp, 'lib/rubo.rb')
[@out.include?('rubocop:disable Style/Documentation'),
 @out.include?('rubocop:disable Metrics/ClassLength'),
 @out.start_with?("# lib/rubo.rb\n#\n# frozen_string_literal: true\n\n")]
#=> [true, true, true]

## Ruby file with a multi-line license stub is preserved below the header
@tmp, @script = stage_repo
write_file(@tmp, 'lib/lic.rb', <<~RB)
  # lib/lic.rb
  # Copyright 2026 Example Corp.
  # Licensed under the MIT License.
  # See LICENSE.txt for details.
  # Author: J. Doe

  module Lic; end
RB
run_fix(@tmp, @script, 'lib/lic.rb')
@out = read_file(@tmp, 'lib/lic.rb')
[@out.include?('Copyright 2026 Example Corp.'),
 @out.include?('Licensed under the MIT License.'),
 @out.include?('Author: J. Doe'),
 @out.start_with?("# lib/lic.rb\n#\n# frozen_string_literal: true\n\n")]
#=> [true, true, true, true]

## Python file with encoding cookie is preserved
@tmp, @script = stage_repo
write_file(@tmp, 'py/enc.py', <<~PY)
  # py/enc.py
  # -*- coding: utf-8 -*-
  x = 1
PY
run_fix(@tmp, @script, 'py/enc.py')
@out = read_file(@tmp, 'py/enc.py')
[@out.include?('# -*- coding: utf-8 -*-'),
 @out.include?('x = 1'),
 @out.start_with?("# py/enc.py\n\n")]
#=> [true, true, true]

## Python file with module docstring is preserved
@tmp, @script = stage_repo
write_file(@tmp, 'py/doc.py', <<~PY)
  # py/doc.py
  """Module docstring.

  More details here.
  """

  def main():
      pass
PY
run_fix(@tmp, @script, 'py/doc.py')
@out = read_file(@tmp, 'py/doc.py')
[@out.include?('"""Module docstring.'),
 @out.include?('More details here.'),
 @out.include?('def main():'),
 @out.start_with?("# py/doc.py\n\n")]
#=> [true, true, true, true]

## Already-conformant Ruby file is a byte-identical no-op under --fix
@tmp, @script = stage_repo
@content = "# lib/ok.rb\n#\n# frozen_string_literal: true\n\nclass Ok; end\n"
write_file(@tmp, 'lib/ok.rb', @content)
run_fix(@tmp, @script, 'lib/ok.rb')
read_file(@tmp, 'lib/ok.rb') == @content
#=> true

## Already-conformant Ruby file passes check mode
@tmp, @script = stage_repo
write_file(@tmp, 'lib/ok.rb', "# lib/ok.rb\n#\n# frozen_string_literal: true\n\nclass Ok; end\n")
@stdout, _err, @status = run_check(@tmp, @script, 'lib/ok.rb')
[@status.exitstatus, @stdout.include?('All file headers are valid')]
#=> [0, true]

## Ruby file with shebang keeps shebang on line 1, header on line 2
@tmp, @script = stage_repo
write_file(@tmp, 'bin/cli.rb', <<~RB)
  #!/usr/bin/env ruby
  # bin/cli.rb
  # frozen_string_literal: true

  puts 'hi'
RB
run_fix(@tmp, @script, 'bin/cli.rb')
@out = read_file(@tmp, 'bin/cli.rb')
[@out.start_with?("#!/usr/bin/env ruby\n# bin/cli.rb\n#\n# frozen_string_literal: true\n\n"),
 @out.include?("puts 'hi'")]
#=> [true, true]

## File missing header entirely gets one added, content preserved
@tmp, @script = stage_repo
write_file(@tmp, 'lib/bare.rb', "class Bare\n  def foo; end\nend\n")
run_fix(@tmp, @script, 'lib/bare.rb')
@out = read_file(@tmp, 'lib/bare.rb')
[@out.start_with?("# lib/bare.rb\n#\n# frozen_string_literal: true\n\n"),
 @out.include?('class Bare'),
 @out.include?('def foo; end')]
#=> [true, true, true]

## Caveat: stale wrong-path header is preserved as content (post-fix behavior)
# After a rename, an old `# old/path.rb` header in a file whose actual path
# is `new/path.rb` no longer matches the positional pattern, so the positional
# matcher leaves it alone and it is preserved as content. The new correct
# header is prepended above it.
@tmp, @script = stage_repo
write_file(@tmp, 'new/path.rb', <<~RB)
  # old/path.rb
  # frozen_string_literal: true

  class Renamed; end
RB
run_fix(@tmp, @script, 'new/path.rb')
@out = read_file(@tmp, 'new/path.rb')
[@out.start_with?("# new/path.rb\n#\n# frozen_string_literal: true\n\n"),
 @out.include?('# old/path.rb'),
 @out.include?('class Renamed; end')]
#=> [true, true, true]

# Teardown
FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
