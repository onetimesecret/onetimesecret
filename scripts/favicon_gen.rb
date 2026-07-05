#!/usr/bin/env ruby
# frozen_string_literal: true

# favicon_gen.rb — OneTimeSecret favicon generator
#
# Pure-Ruby SVG generation for a small family of two-colour icons, plus a full
# web icon set (SVG, ICO, PNGs, web manifest). No image gems required.
#
# Rasterisation is delegated to rsvg-convert (preferred) or ImageMagick. The
# .ico container is assembled in pure Ruby by packing PNGs — no extra tools.
#
# Usage:
#   ruby favicon_gen.rb --bg "#d8412f" --fg "#ffffff" --style hourglass --out ./public
#   ruby favicon_gen.rb --bg "#0b0d10" --fg "#67e8f9" --style arc       --out ./public
#   ruby scripts/favicon_gen.rb --bg "#053359" --fg "#eee" --style stopwatch --out ./tmp/public
#
# Styles: hourglass | arc | comet | clocklock | lock
#
# The SVG is the source of truth; everything else is derived from it.

require "open3"
require "fileutils"
require "zlib"

module Favicon
  STYLES = %w[hourglass arc comet clocklock lock
              timer stopwatch clockface sundial sextant
              timerpie shield lockopen].freeze

  # All glyphs are authored on a 32x32 grid. Foreground geometry is kept inside
  # the central ~80% so the icon survives Android/iOS maskable safe zones.
  VIEW = 32.0

  module_function

  # ---- colour ---------------------------------------------------------------

  def norm_hex(c)
    c = c.to_s.strip
    c = c.delete_prefix("#")
    c = c.chars.map { |ch| ch * 2 }.join if c.length == 3
    raise ArgumentError, "bad hex colour: #{c.inspect}" unless c.match?(/\A[0-9a-fA-F]{6}\z/)
    "#" + c.downcase
  end

  # Relative luminance (sRGB) — used only to pick a sensible default fg if the
  # caller supplies one colour, and to warn on low-contrast pairs.
  def luminance(hex)
    r, g, b = hex.delete_prefix("#").scan(/../).map { |h| h.to_i(16) / 255.0 }
    lin = ->(c) { c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    0.2126 * lin.(r) + 0.7152 * lin.(g) + 0.0722 * lin.(b)
  end

  def contrast_ratio(a, b)
    la, lb = luminance(a), luminance(b)
    hi, lo = [la, lb].max, [la, lb].min
    (hi + 0.05) / (lo + 0.05)
  end

  # ---- SVG body -------------------------------------------------------------

  # radius: corner rounding for the background square (0 = full square, used for
  #         iOS/Android PNGs which get masked by the OS).
  def svg(style:, bg:, fg:, radius: 6.4, title: "OneTimeSecret")
    bg = norm_hex(bg)
    fg = norm_hex(fg)
    raise ArgumentError, "unknown style #{style.inspect}" unless STYLES.include?(style.to_s)

    body = send("glyph_#{style}", fg, bg)
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32" role="img" aria-label="#{title}">
        <rect width="32" height="32" rx="#{fmt radius}" fill="#{bg}"/>
      #{indent body, 2}
      </svg>
    SVG
  end

  # ---- glyphs ---------------------------------------------------------------
  # Each returns SVG fragment(s) drawn in fg over the bg square.

  # Filled hourglass. Bold bowtie + two caps. The pinched waist reads as a
  # keyhole at a glance, bridging the ephemerality and security threads.
  def glyph_hourglass(fg, _bg)
    <<~G
      <g fill="#{fg}">
        <rect x="8" y="6"    width="16" height="2" rx="1"/>
        <rect x="8" y="24"   width="16" height="2" rx="1"/>
        <path d="M10.2 8 H21.8 L16 16 L21.8 24 H10.2 L16 16 Z"/>
      </g>
    G
  end

  # Countdown arc: a thick ring draining from the top. Round caps keep the two
  # ends from looking like a broken stroke at small sizes.
  def glyph_arc(fg, _bg)
    # 280-degree sweep, 80-degree gap centred at 12 o'clock.
    r = 10.0
    cx = cy = 16.0
    gap_half = 40.0 # degrees
    start_a = -90 + gap_half      # leading (right) end of the gap
    end_a   = -90 - gap_half + 360 # trailing (left) end, going clockwise
    p1 = polar(cx, cy, r, start_a)
    p2 = polar(cx, cy, r, end_a)
    <<~G
      <path d="M#{fmt p1[0]} #{fmt p1[1]} A#{fmt r} #{fmt r} 0 1 1 #{fmt p2[0]} #{fmt p2[1]}"
            fill="none" stroke="#{fg}" stroke-width="4.4" stroke-linecap="round"/>
    G
  end

  # Comet: a head with a fading trail. The most minimal mark — verified to be
  # the weakest at 16px, kept as a candidate for larger-only contexts.
  def glyph_comet(fg, _bg)
    head = [21.0, 11.0, 4.2]
    trail = [
      [16.6, 15.4, 3.1, 0.70],
      [12.9, 19.1, 2.2, 0.46],
      [10.0, 22.0, 1.4, 0.28],
      [7.8,  24.2, 0.8, 0.16],
    ]
    dots = trail.map do |x, y, rr, op|
      %(<circle cx="#{fmt x}" cy="#{fmt y}" r="#{fmt rr}" fill="#{fg}" fill-opacity="#{op}"/>)
    end
    <<~G
      #{dots.join("\n")}
      <circle cx="#{fmt head[0]}" cy="#{fmt head[1]}" r="#{fmt head[2]}" fill="#{fg}"/>
    G
  end

  # Clock-lock hybrid: lock body with a shackle that arcs like a clock hand over
  # a ghosted dial. Conceptually rich; busiest of the set.
  def glyph_clocklock(fg, bg)
    <<~G
      <circle cx="16" cy="16" r="10.5" fill="none" stroke="#{fg}" stroke-width="1.4" stroke-opacity="0.22"/>
      <path d="M11 15 V12.5 A5 5 0 0 1 21 12.5 V15"
            fill="none" stroke="#{fg}" stroke-width="2.6" stroke-linecap="round"/>
      <rect x="9.5" y="15" width="13" height="10.5" rx="2.2" fill="#{fg}"/>
      <circle cx="16" cy="19.2" r="1.5" fill="#{bg}"/>
      <rect x="15.25" y="19.2" width="1.5" height="3.2" rx="0.75" fill="#{bg}"/>
    G
  end

  # Plain padlock — the security baseline (Twemoji-style proportions). Shackle
  # visibly connects into the body; keyhole is a circle + slot.
  def glyph_lock(fg, bg)
    <<~G
      <path d="M11.5 15 V12 A4.5 4.5 0 0 1 20.5 12 V15"
            fill="none" stroke="#{fg}" stroke-width="2.6" stroke-linecap="round"/>
      <rect x="8.5" y="14.5" width="15" height="11.5" rx="2.6" fill="#{fg}"/>
      <circle cx="16" cy="19.4" r="1.7" fill="#{bg}"/>
      <rect x="15.15" y="19.4" width="1.7" height="3.6" rx="0.85" fill="#{bg}"/>
    G
  end

  # Countdown timer: round body, top push-button, hand set to a duration.
  def glyph_timer(fg, _bg)
    <<~G
      <g fill="none" stroke="#{fg}" stroke-width="2.2" stroke-linecap="round">
        <circle cx="16" cy="18" r="8.4"/>
        <path d="M16 18 L20.4 13.6"/>
      </g>
      <g fill="#{fg}">
        <rect x="14.4" y="4.6" width="3.2" height="2.6" rx="0.8"/>
        <rect x="15.2" y="6.8" width="1.6" height="3"/>
        <circle cx="16" cy="18" r="1.15"/>
      </g>
    G
  end

  # Stopwatch: crown button plus two angled lugs and a sweeping hand.
  def glyph_stopwatch(fg, _bg)
    <<~G
      <g fill="none" stroke="#{fg}" stroke-width="2.1" stroke-linecap="round">
        <circle cx="16" cy="18" r="8"/>
        <path d="M10.7 11.6 L8.7 9"/>
        <path d="M21.3 11.6 L23.3 9"/>
        <path d="M16 18 L16 11.9"/>
      </g>
      <g fill="#{fg}">
        <rect x="14.7" y="4.4" width="2.6" height="2.2" rx="0.7"/>
        <rect x="15.3" y="6.4" width="1.4" height="2.4"/>
        <circle cx="16" cy="18" r="1.1"/>
      </g>
    G
  end

  # Plain clock face: rim, four quarter ticks, two hands.
  def glyph_clockface(fg, _bg)
    <<~G
      <circle cx="16" cy="16" r="9.4" fill="none" stroke="#{fg}" stroke-width="2.2"/>
      <g fill="#{fg}">
        <rect x="15.2" y="7.6"  width="1.6" height="2.2" rx="0.6"/>
        <rect x="22.2" y="15.2" width="2.2" height="1.6" rx="0.6"/>
        <rect x="15.2" y="22.2" width="1.6" height="2.2" rx="0.6"/>
        <rect x="7.6"  y="15.2" width="2.2" height="1.6" rx="0.6"/>
      </g>
      <g fill="none" stroke="#{fg}" stroke-linecap="round">
        <path d="M16 16 L16 10.6" stroke-width="2.4"/>
        <path d="M16 16 L20.2 18"  stroke-width="1.9"/>
      </g>
      <circle cx="16" cy="16" r="1.15" fill="#{fg}"/>
    G
  end

  # Sundial: a dial rim over a base plate, hour lines, and a gnomon casting up.
  def glyph_sundial(fg, _bg)
    <<~G
      <path d="M7 22 A9 9 0 0 1 25 22" fill="none" stroke="#{fg}" stroke-width="1.8" stroke-opacity="0.85"/>
      <g stroke="#{fg}" stroke-width="1.3" stroke-linecap="round" stroke-opacity="0.55">
        <path d="M16 21 L9.6 16.2"/>
        <path d="M16 21 L22.4 16.2"/>
      </g>
      <path d="M16 21 L13 21 L16 13.4 Z" fill="#{fg}"/>
      <rect x="6.5" y="21" width="19" height="2" rx="1" fill="#{fg}"/>
    G
  end

  # Sextant: wedge frame, graduated limb arc, index arm, and a sighting scope.
  def glyph_sextant(fg, _bg)
    <<~G
      <g fill="none" stroke="#{fg}" stroke-linecap="round">
        <path d="M16 7.5 L9 22"   stroke-width="2"/>
        <path d="M16 7.5 L23 22"  stroke-width="2"/>
        <path d="M9 22 A10.5 10.5 0 0 1 23 22" stroke-width="2.8"/>
        <path d="M16 8 L19.4 21" stroke-width="1.7"/>
      </g>
      <circle cx="16" cy="7.4" r="1.9" fill="#{fg}"/>
    G
  end

  # Timer (pie): solid disc with a wedge of elapsed time cut to the background.
  # The boldest, most legible mark at 16px; the bite reads as "draining".
  def glyph_timerpie(fg, bg)
    <<~G
      <circle cx="16" cy="18" r="8.6" fill="#{fg}"/>
      <path d="M16 18 L16 9.4 A8.6 8.6 0 0 1 22.08 11.92 Z" fill="#{bg}"/>
      <g fill="#{fg}">
        <rect x="14.3" y="4.4" width="3.4" height="2.7" rx="0.8"/>
        <rect x="15.15" y="6.6" width="1.7" height="3.1"/>
      </g>
    G
  end

  # Shield carrying a keyhole — bold filled silhouette, strongest security read.
  def glyph_shield(fg, bg)
    <<~G
      <path d="M16 5 L25 8.2 V15.5 C25 20.8 21.2 24.6 16 27.2 C10.8 24.6 7 20.8 7 15.5 V8.2 Z" fill="#{fg}"/>
      <circle cx="16" cy="14.8" r="2.1" fill="#{bg}"/>
      <rect x="15.05" y="14.8" width="1.9" height="4.4" rx="0.9" fill="#{bg}"/>
    G
  end

  # Opened padlock — the "secret has been read" state. Right leg lifts clear of
  # the body. Distinguishable only at 32px+; intended as a state, not a favicon.
  def glyph_lockopen(fg, bg)
    <<~G
      <path d="M11.5 15 V11 A4.5 4.5 0 0 1 20.5 11 V13" fill="none" stroke="#{fg}" stroke-width="2.6" stroke-linecap="round"/>
      <rect x="8.5" y="15" width="15" height="11" rx="2.6" fill="#{fg}"/>
      <circle cx="16" cy="19.6" r="1.7" fill="#{bg}"/>
      <rect x="15.15" y="19.6" width="1.7" height="3.4" rx="0.85" fill="#{bg}"/>
    G
  end

  # ---- geometry / format helpers -------------------------------------------

  def polar(cx, cy, r, deg)
    rad = deg * Math::PI / 180.0
    [cx + r * Math.cos(rad), cy + r * Math.sin(rad)]
  end

  def fmt(n)
    s = format("%.3f", n.to_f)
    s = s.sub(/\.?0+\z/, "")
    s.empty? || s == "-0" ? "0" : s
  end

  def indent(text, n)
    pad = " " * n
    text.each_line.map { |l| l.strip.empty? ? l : pad + l }.join
  end

  # ---- rasterisation --------------------------------------------------------

  def rasteriser
    @rasteriser ||= if which("rsvg-convert")
      :rsvg
    elsif which("magick") || which("convert")
      :imagemagick
    else
      raise "need rsvg-convert or ImageMagick to rasterise PNGs"
    end
  end

  def which(bin)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, bin))
    end
  end

  def png_bytes(svg_string, size)
    case rasteriser
    when :rsvg
      run(["rsvg-convert", "-w", size.to_s, "-h", size.to_s, "--background-color", "none"], stdin: svg_string)
    when :imagemagick
      bin = which("magick") ? "magick" : "convert"
      # -background none keeps transparency outside the rounded corners.
      run([bin, "-background", "none", "-density", "384", "svg:-", "-resize", "#{size}x#{size}", "png:-"], stdin: svg_string)
    end
  end

  def run(cmd, stdin: nil)
    out, err, st = Open3.capture3(*cmd, stdin_data: stdin)
    raise "#{cmd.first} failed: #{err}" unless st.success?
    out.b # binary — these are raw PNG bytes, not text
  end

  # ---- pure-Ruby ICO packing -----------------------------------------------
  # PNG-format ICO (supported by every browser since IE11). Container = 6-byte
  # header + 16-byte directory entry per image + concatenated PNG payloads.

  def ico(png_by_size)
    entries = png_by_size.sort_by { |sz, _| sz }
    count = entries.length
    header = [0, 1, count].pack("vvv")
    dir_size = 16 * count
    offset = 6 + dir_size
    dir = String.new(encoding: Encoding::BINARY)
    blobs = String.new(encoding: Encoding::BINARY)
    entries.each do |sz, png|
      w = sz >= 256 ? 0 : sz
      h = sz >= 256 ? 0 : sz
      dir << [w, h, 0, 0, 1, 32, png.bytesize, offset].pack("CCCCvvVV")
      blobs << png
      offset += png.bytesize
    end
    header.b + dir + blobs
  end

  # ---- full icon set --------------------------------------------------------

  def build_set(bg:, fg:, style:, out:, name: "OneTimeSecret", short: "OTS", theme: nil)
    FileUtils.mkdir_p(out)
    bg = norm_hex(bg)
    fg = norm_hex(fg)
    theme ||= bg

    cr = contrast_ratio(bg, fg)
    warn "  ! low contrast (#{cr.round(2)}:1) — aim for >= 3:1 for favicon legibility" if cr < 3.0

    rounded = svg(style: style, bg: bg, fg: fg, radius: 6.4)   # tab/SVG/ICO
    square  = svg(style: style, bg: bg, fg: fg, radius: 0.0)   # OS-masked PNGs

    File.write(File.join(out, "favicon.svg"), rounded)

    ico_pngs = { 16 => png_bytes(rounded, 16), 32 => png_bytes(rounded, 32), 48 => png_bytes(rounded, 48) }
    File.binwrite(File.join(out, "favicon.ico"), ico(ico_pngs))

    File.binwrite(File.join(out, "apple-touch-icon.png"),     png_bytes(square, 180))
    File.binwrite(File.join(out, "android-chrome-192x192.png"), png_bytes(square, 192))
    File.binwrite(File.join(out, "android-chrome-512x512.png"), png_bytes(square, 512))

    File.write(File.join(out, "site.webmanifest"), manifest(name, short, theme, bg))
    out
  end

  def manifest(name, short, theme, bg)
    <<~JSON
      {
        "name": "#{name}",
        "short_name": "#{short}",
        "icons": [
          { "src": "/android-chrome-192x192.png", "sizes": "192x192", "type": "image/png", "purpose": "any maskable" },
          { "src": "/android-chrome-512x512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
        ],
        "theme_color": "#{theme}",
        "background_color": "#{bg}",
        "display": "standalone"
      }
    JSON
  end
end

# ---- CLI --------------------------------------------------------------------

if $PROGRAM_NAME == __FILE__
  require "optparse"
  opts = { bg: "#d8412f", fg: "#ffffff", style: "hourglass", out: "./public" }
  OptionParser.new do |o|
    o.banner = "Usage: ruby favicon_gen.rb [options]"
    o.on("--bg HEX")    { |v| opts[:bg] = v }
    o.on("--fg HEX")    { |v| opts[:fg] = v }
    o.on("--style S", Favicon::STYLES) { |v| opts[:style] = v }
    o.on("--out DIR")   { |v| opts[:out] = v }
    o.on("--name NAME") { |v| opts[:name] = v }
  end.parse!

  out = Favicon.build_set(bg: opts[:bg], fg: opts[:fg], style: opts[:style],
                          out: opts[:out], name: opts[:name] || "OneTimeSecret")
  puts "Wrote #{Favicon::STYLES.include?(opts[:style]) ? opts[:style] : '?'} icon set to #{out}/"
end
