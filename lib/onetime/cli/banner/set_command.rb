# lib/onetime/cli/banner/set_command.rb
#
# frozen_string_literal: true

#
# CLI command for setting the global broadcast banner.
#
# Dry-run is the default — prints the valkey-cli commands it would run
# and renders an ASCII preview. Pass --apply to actually write.
#
# Usage:
#   bin/ots banner set "Scheduled maintenance Sun 02:00 UTC"
#   bin/ots banner set '<a href="/status">Maintenance notice</a>' --apply
#   bin/ots banner set --file banner.html --apply
#   bin/ots banner set --file - --apply              # read from stdin
#   bin/ots banner set "temp notice" --ttl 3600      # auto-expire in 1 hour
#

module Onetime
  module CLI
    module Banner
      class SetCommand < Command
        desc 'Set the global broadcast banner (dry-run by default)'

        argument :content,
          type: :string,
          required: false,
          desc: 'Banner content (HTML allowed; frontend sanitizes to <a> tags only)'

        option :apply,
          type: :boolean,
          default: false,
          desc: 'Actually write to Redis (default is dry-run)'
        option :file,
          type: :string,
          aliases: ['f'],
          desc: 'Read content from file (use - for stdin)'
        option :ttl,
          type: :integer,
          aliases: ['t'],
          desc: 'Auto-expire banner after this many seconds'

        def call(content: nil, apply: false, file: nil, ttl: nil, **)
          boot_application!

          banner_text = resolve_content(content, file)

          unless banner_text
            warn 'Error: provide banner content as an argument or via --file'
            exit 1
          end

          if banner_text.empty?
            warn 'Error: banner content is empty'
            exit 1
          end

          display_preview(banner_text)

          if apply
            write_banner(banner_text, ttl)
          else
            display_dry_run(banner_text, ttl)
          end
        end

        private

        def resolve_content(content, file)
          if file
            if file == '-'
              $stdin.read.strip
            elsif File.exist?(file)
              File.read(file).strip
            else
              warn "Error: file not found: #{file}"
              exit 1
            end
          else
            content
          end
        end

        def display_preview(banner_text)
          plain = strip_html(banner_text)

          puts
          puts 'Preview (sanitized, links shown as text):'

          top    = "┌#{ "─" * 60 }┐"
          mid    = "├#{ "─" * 60 }┤"
          bottom = "└#{ "─" * 60 }┘"

          banner_line = format_centered(plain, 56)

          puts top
          puts "│ \u{1F4E2}  #{banner_line} [x] │"
          puts mid
          puts "│  [ logo ]                                  Sign In   Sign Up │"
          puts "│#{' ' * 60}│"
          puts "│#{center_text('Paste a password, secret', 60)}│"
          puts "│#{center_text('message or private link.', 60)}│"
          puts "│#{center_text("┌#{ "─" * 30 }┐", 60)}│"
          puts "│#{center_text("│#{' ' * 30}│", 60)}│"
          puts "│#{center_text("└#{ "─" * 30 }┘", 60)}│"
          puts "│#{center_text('[ Create a secret link ]', 60)}│"
          puts "│#{' ' * 60}│"
          puts bottom
        end

        def display_dry_run(banner_text, ttl)
          escaped = shell_escape(banner_text)

          puts
          puts 'Would run (re-run with --apply to write):'
          puts '  # DB 0'
          if ttl
            puts "  SET global_banner '#{escaped}' EX #{ttl}"
          else
            puts "  SET global_banner '#{escaped}'"
          end
          puts '  # then refresh runtime: Onetime::Runtime.update_features(global_banner: ...)'
        end

        def write_banner(banner_text, ttl)
          db = Familia.dbclient(0)

          if ttl
            db.setex('global_banner', ttl, banner_text)
          else
            db.set('global_banner', banner_text)
          end

          Onetime::Runtime.update_features(global_banner: banner_text)

          puts
          puts 'Banner set.'

          if ttl
            puts format('  Expires in: %s (%d seconds)', humanize_seconds(ttl), ttl)
          else
            puts '  Expires: never (clear manually with `bin/ots banner clear --apply`)'
          end

          puts
          puts 'Note: runtime refresh reaches this process only.'
          puts 'Other running processes will pick it up on next boot or re-read.'
        end

        def strip_html(html)
          html
            .gsub(/<a\s[^>]*>/, '')
            .gsub(%r{</a>}, '')
            .gsub(/<[^>]+>/, '')
            .gsub(/&amp;/, '&')
            .gsub(/&lt;/, '<')
            .gsub(/&gt;/, '>')
            .gsub(/&quot;/, '"')
            .gsub(/&#39;/, "'")
            .strip
        end

        def shell_escape(str)
          str.gsub("'", "'\\\\''")
        end

        def format_centered(text, width)
          if text.length >= width
            text[0, width]
          else
            text.ljust(width)
          end
        end

        def center_text(text, width)
          if text.length >= width
            text[0, width]
          else
            pad = (width - text.length) / 2
            (' ' * pad) + text + (' ' * (width - text.length - pad))
          end
        end

        def humanize_seconds(seconds)
          if seconds >= 86_400
            format('%dd %dh', seconds / 86_400, (seconds % 86_400) / 3600)
          elsif seconds >= 3600
            format('%dh %dm', seconds / 3600, (seconds % 3600) / 60)
          elsif seconds >= 60
            format('%dm %ds', seconds / 60, seconds % 60)
          else
            format('%ds', seconds)
          end
        end
      end
    end

    register 'banner set', Banner::SetCommand
  end
end
