#!/usr/bin/env ruby
# frozen_string_literal: true

# adr-lint - verify every ADR-NNN#slug reference in the repo resolves.
#
# Usage:
#   bin/adr-lint                 # lint whole repo (git-tracked files)
#   bin/adr-lint path [path...]  # lint specific files/dirs
#
# Escape hatches for documents that cite ADRs illustratively:
#   <!-- adr-lint: ignore-file -->   anywhere in the file
#   adr-lint:ignore                  anywhere on a line
# Fenced code blocks in .md files are skipped automatically.
#
# Exit 0 when every reference resolves, 1 otherwise.
#
# See ADR-036#ci-enforces-references

require 'set'

ADR_DIR = ENV.fetch('ADR_DIR', 'docs/adr')

# ADR-024, ADR-024#slug, adr-024#slug. Captures number and optional slug.
REFERENCE = /\bADR-(\d{3,})(?:#([a-z0-9][a-z0-9-]*))?/i

# Skip binaries and anything that would produce noise.
SKIP_EXT = %w[.png .jpg .jpeg .gif .pdf .zip .gz .ico .woff .woff2 .ttf
              .lock .min.js .map].to_set

# Tiny Levenshtein for the "did you mean" hint.
def levenshtein(a, b)
  return b.size if a.empty?
  return a.size if b.empty?

  prev = (0..b.size).to_a
  a.each_char.with_index do |ca, i|
    cur = [i + 1]
    b.each_char.with_index do |cb, j|
      cur << [prev[j + 1] + 1, cur[j] + 1, prev[j] + (ca == cb ? 0 : 1)].min
    end
    prev = cur
  end
  prev.last
end

# Anchors are DECLARED, not derived (ADR-036#anchors-are-declared). Derived
# slugs are computed only to power the "heading exists but has no anchor" hint.
def slugify(heading)
  heading.downcase
         .gsub(/`([^`]*)`/, '\1')          # inline code contributes its text
         .gsub(/\[([^\]]*)\]\([^)]*\)/, '\1') # links contribute their label
         .gsub(/[^\p{Word}\- ]/, '')
         .strip
         .tr(' ', '-')
end

# Build number -> {path:, anchors: Set} from the ADR directory.
def load_adrs
  adrs = {}
  Dir.glob(File.join(ADR_DIR, 'adr-*.md')).sort.each do |path|
    num = File.basename(path)[/adr-(\d+)/i, 1] or next
    anchors = Set.new     # declared: {#slug} or <a id="slug">
    derived = Set.new     # heading text slugified, for hints only
    in_fence = false
    File.foreach(path, encoding: 'UTF-8') do |line|
      if line.start_with?('```', '~~~')
        in_fence = !in_fence
        next
      end
      next if in_fence

      case line
      when /^(\#+)\s+(.*?)\s*(?:\{\#([a-z0-9][a-z0-9-]*)\})?\s*$/
        text = Regexp.last_match(2)
        explicit = Regexp.last_match(3)
        explicit ? anchors << explicit : derived << slugify(text)
      when /<a\s+id=["']([a-z0-9][a-z0-9-]*)["']/i
        anchors << Regexp.last_match(1) # transitional alias
      end
    end
    adrs[num.to_i] = { path: path, anchors: anchors, derived: derived }
  end
  adrs
end

def candidate_files(args)
  if args.empty?
    `git ls-files -z`.split("\x0")
  else
    args.flat_map { |a| File.directory?(a) ? Dir.glob("#{a}/**/*") : [a] }
  end.reject do |f|
    !File.file?(f) || SKIP_EXT.include?(File.extname(f).downcase)
  end
end

adrs = load_adrs
if adrs.empty?
  warn "adr-lint: no ADRs found in #{ADR_DIR} (set ADR_DIR to override)"
  exit 1
end

failures = []
seen = 0

candidate_files(ARGV).each do |file|
  text = File.read(file, encoding: 'UTF-8', invalid: :replace, undef: :replace)
  next unless text.match?(REFERENCE)
  next if text.match?(/adr-lint:\s*ignore-file/i)

  markdown = File.extname(file).casecmp('.md').zero?
  in_fence = false

  text.each_line.with_index(1) do |line, lineno|
    if markdown && line.start_with?('```', '~~~')
      in_fence = !in_fence
      next
    end
    next if in_fence                       # illustrative refs in code samples
    next if line.match?(/adr-lint:\s*ignore\b/i)

    line.scan(REFERENCE) do |num_s, slug_s|
      num = num_s.to_i
      slug = slug_s&.downcase
      seen += 1
      adr = adrs[num]

      if adr.nil?
        failures << [file, lineno, "ADR-#{format('%03d', num)} does not exist"]
      elsif slug && !adr[:anchors].include?(slug)
        hint =
          if adr[:derived].include?(slug)
            " (a heading matches but declares no anchor - add {##{slug}} to it)"
          else
            near = adr[:anchors].min_by { |a| levenshtein(a, slug) }
            near ? " (closest declared anchor: ##{near})" : ''
          end
        failures << [file, lineno,
                     "ADR-#{format('%03d', num)}##{slug} not found in " \
                     "#{adr[:path]}#{hint}"]
      end
    end
  end
end

if failures.empty?
  puts "adr-lint: #{seen} reference(s) across #{adrs.size} ADR(s) — all resolve"
  exit 0
end

failures.each { |file, lineno, msg| warn "#{file}:#{lineno}: #{msg}" }
warn "\nadr-lint: #{failures.size} broken reference(s) of #{seen} checked"
warn 'A moved decision should leave a forwarding anchor. See ADR-036#moving-leaves-a-forwarding-anchor'
exit 1
