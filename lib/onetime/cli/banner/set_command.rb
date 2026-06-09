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
    class BannerSetCommand < Command
      desc 'Set the global broadcast banner (dry-run by default)'

      argument :content,
        type: :string,
        required: false,
        desc: 'Banner content (HTML; frontend sanitizes to <a> tags only)'

      option :apply,
        type: :boolean,
        default: false,
        desc: 'Actually write to Redis (default is dry-run)'
      option :file,
        type: :string,
        aliases: ['f'],
        desc: 'Read content from file (use - for stdin); takes precedence over argument'
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

        render_preview(banner_text)

        if apply
          write_banner(banner_text, ttl)
        else
          render_dry_run(banner_text, ttl)
        end
      end

      private

      def resolve_content(content, file)
        return content unless file

        if file == '-'
          $stdin.read.strip
        elsif File.exist?(file)
          File.read(file).strip
        else
          warn "Error: file not found: #{file}"
          exit 1
        end
      end

      # Renders an ASCII mock of the page with the banner across the
      # top so the operator can see roughly how it lands.
      #
      # Content is stripped of HTML and decoded (same result as the
      # frontend's DOMPurify pass rendered as plain text).
      INNER_WIDTH = 62

      def render_preview(banner_text)
        plain = strip_html(banner_text)

        # Banner row budget (display columns):
        #   " "(1) + megaphone(2) + "  "(2) + text + "  "(2) + "[x]"(3) + " "(1) = 11 fixed
        text_budget = INNER_WIDTH - 11
        display = if plain.length > text_budget
                    "#{plain[0, text_budget - 3]}..."
                  else
                    plain
                  end

        banner_fill = ' ' * (text_budget - display.length)

        header = '  [ logo ]'
        nav    = 'Sign In   Sign Up '
        gap    = ' ' * (INNER_WIDTH - header.length - nav.length)

        puts
        puts 'Preview (sanitized, links shown as text):'
        puts "┌#{"─" * INNER_WIDTH}┐"
        puts "│ \u{1F4E2}  #{display}#{banner_fill}  [x] │"
        puts "├#{"─" * INNER_WIDTH}┤"
        puts "│#{pad(header + gap + nav)}│"
        puts "│#{pad('')}│"
        puts "│#{center('Paste a password, secret')}│"
        puts "│#{center('message or private link.')}│"
        puts "│#{center("┌#{"─" * 32}┐")}│"
        puts "│#{center("│#{' ' * 32}│")}│"
        puts "│#{center("└#{"─" * 32}┘")}│"
        puts "│#{center('[ Create a secret link ]')}│"
        puts "│#{pad('')}│"
        puts "└#{"─" * INNER_WIDTH}┘"
      end

      def render_dry_run(banner_text, ttl)
        escaped = banner_text.gsub("'", "'\\\\''")

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
          .gsub('&amp;', '&')
          .gsub('&lt;', '<')
          .gsub('&gt;', '>')
          .gsub('&quot;', '"')
          .gsub('&#39;', "'")
          .gsub(/<[^>]+>/, '')
          .strip
      end

      def pad(text)
        text.ljust(INNER_WIDTH)[0, INNER_WIDTH]
      end

      def center(text)
        return text[0, INNER_WIDTH] if text.length >= INNER_WIDTH

        pad_left = (INNER_WIDTH - text.length) / 2
        "#{' ' * pad_left}#{text}".ljust(INNER_WIDTH)
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

    register 'banner set', BannerSetCommand
  end
end
