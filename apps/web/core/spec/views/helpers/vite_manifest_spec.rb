# apps/web/core/spec/views/helpers/vite_manifest_spec.rb
#
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

require_relative '../../../../../../spec/spec_helper'

require_relative '../../../views/helpers/vite_manifest'

# Tests for Core::Views::ViteManifest, the helper that turns a Vite manifest
# into the <script>/<link> tags the HTML shell emits.
#
# What these lock down is the render path of the secret link page (#4288):
# what the shell tells the browser to fetch at high priority before it can
# paint anything. Two invariants:
#
#   1. The shell preloads the ACTIVE locale's messages asset, and only that
#      one. Whether the fetch in src/i18n.ts overlaps the JS bundle or queues
#      behind it hangs on this hint being present and correct.
#   2. The shell preloads no fonts. It used to preload every font in the
#      manifest -- eight files, ~675 KB, ahead of the bytes the page actually
#      needs to render.
RSpec.describe Core::Views::ViteManifest do
  # Bare includer: the helper needs nothing from BaseView, and going through
  # the view stack would make these assertions about serializers instead.
  let(:includer_class) do
    Class.new do
      include Core::Views::ViteManifest
    end
  end

  subject(:helper) { includer_class.new }

  let(:public_dir) { Dir.mktmpdir('vite-manifest-spec') }
  let(:nonce) { 'test-nonce' }

  # Mirrors a real build: one chunk, one stylesheet, per-locale JSON assets
  # for every locale EXCEPT the one bundled into the chunk (en), plus the
  # font files the stylesheet references.
  let(:manifest) do
    {
      'main.ts' => {
        'file' => 'assets/main.abc123.js',
        'name' => 'main',
        'src' => 'main.ts',
        'isEntry' => true,
        'assets' => [
          'assets/de.d3adb33f.json',
          'assets/de_AT.c0ffee12.json',
          'assets/pt_BR.f00dcafe.json',
          'assets/ZillaSlab-Regular.aaaa1111.woff2',
          'assets/ZillaSlab-Regular.bbbb2222.woff',
          'assets/ZillaSlab-Bold.cccc3333.woff2',
        ],
      },
      'style.css' => { 'file' => 'assets/style.def456.css' },
    }
  end

  def write_manifest(data = manifest, filename: 'manifest.json')
    dir = File.join(public_dir, 'dist', '.vite')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, filename), JSON.generate(data))
  end

  before do
    stub_const('Core::Views::ViteManifest::PUBLIC_DIR', public_dir)
    write_manifest
  end

  after do
    FileUtils.remove_entry(public_dir) if Dir.exist?(public_dir)
  end

  describe 'the shell tags' do
    subject(:html) { helper.vite_assets(nonce: nonce, development: false, locale: 'de') }

    it 'links the entry chunk and the stylesheet' do
      expect(html).to include('<script type="module" nonce="test-nonce" src="/dist/assets/main.abc123.js"></script>')
      expect(html).to include('<link rel="stylesheet" nonce="test-nonce" href="/dist/assets/style.def456.css">')
    end

    it 'preloads no fonts' do
      expect(html).not_to include('as="font"')
      expect(html).not_to include('.woff')
    end
  end

  describe 'locale messages preload' do
    def preloads(locale)
      helper
        .vite_assets(nonce: nonce, development: false, locale: locale)
        .lines
        .map(&:strip)
        .select { |line| line.include?('rel="preload"') }
    end

    it 'preloads the active locale, and only the active locale' do
      expect(preloads('de')).to contain_exactly(
        '<link rel="preload" nonce="test-nonce" href="/dist/assets/de.d3adb33f.json" ' \
        'as="fetch" type="application/json" crossorigin>'
      )
    end

    # `crossorigin` is what makes the hint's credentials mode match the plain
    # fetch(url) in src/i18n.ts. Without it Chrome discards the preloaded
    # response and downloads the locale a second time.
    it 'marks the preload crossorigin' do
      expect(preloads('de').first).to include('crossorigin')
    end

    # de_AT must not be served the `de` asset, nor match it as a prefix.
    it 'distinguishes a regional variant from its base language' do
      expect(preloads('de_AT').first).to include('/dist/assets/de_AT.c0ffee12.json')
      expect(preloads('pt_BR').first).to include('/dist/assets/pt_BR.f00dcafe.json')
    end

    # en is bundled into the chunk, so the build emits no asset for it. That
    # absence -- not a constant duplicated on this side -- is what suppresses
    # the hint. A preload nothing fetches is wasted bandwidth on the critical
    # path and a console warning.
    it 'emits nothing for a locale the build did not externalize' do
      expect(preloads('en')).to be_empty
    end

    it 'emits nothing when no locale is known' do
      expect(preloads(nil)).to be_empty
    end

    # The locale reaches us from request state (Accept-Language, a custom
    # domain's brand settings), so it is pattern-checked before it is used to
    # build a filename matcher.
    it 'rejects a locale that is not a locale code' do
      expect(preloads('../../etc/passwd')).to be_empty
      expect(preloads('de.d3adb33f')).to be_empty
      expect(preloads('a' * 32)).to be_empty
    end

    it 'emits nothing for an unbuilt locale' do
      expect(preloads('zz')).to be_empty
    end

    # vite.config.local.ts builds without content hashes.
    it 'matches an unhashed asset name' do
      write_manifest(
        {
          'main.ts' => {
            'file' => 'assets/main.js',
            'isEntry' => true,
            'assets' => ['assets/de.json', 'assets/de_AT.json'],
          },
        }
      )

      expect(preloads('de').first).to include('/dist/assets/de.json')
      expect(preloads('de_AT').first).to include('/dist/assets/de_AT.json')
    end
  end

  describe 'development mode' do
    it 'serves the entry from the Vite dev server and preloads nothing' do
      html = helper.vite_assets(nonce: nonce, development: true, locale: 'de')

      expect(html).to include('src="/dist/main.ts"')
      expect(html).not_to include('rel="preload"')
    end
  end

  describe 'the admin shell' do
    let(:admin_manifest) do
      { 'admin.ts' => { 'file' => 'assets/admin.999.js', 'isEntry' => true } }
    end

    it 'resolves against its own manifest' do
      write_manifest(admin_manifest, filename: 'manifest-admin.json')

      html = helper.vite_assets(nonce: nonce, development: false, entry: 'admin.ts', locale: 'de')

      expect(html).to include('src="/dist/assets/admin.999.js"')
      expect(html).not_to include('rel="preload"')
    end
  end
end
