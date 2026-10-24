# apps/web/core/spec/views/helpers/vite_manifest_spec.rb
#
# frozen_string_literal: true

# Coverage for the production asset tags ViteManifest builds from the one-pass
# code-split manifest, and for the CSP nonce model they implement: the entry
# script carries the nonce, the chunks it imports statically are preloaded
# with nonced <link rel="modulepreload"> tags, and the csp-nonce meta tag
# hands the nonce to Vite's preload helper for dynamic imports. A preload
# without the nonce is blocked by the nonce-only script-src, after which the
# browser refuses the import of the same chunk and the shell never boots, so
# the nonce on every emitted tag is the load-bearing assertion here.
#
# No Redis or SQL required.

require 'json'
require 'tmpdir'

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/helpers/vite_manifest'

RSpec.describe Core::Views::ViteManifest do
  let(:shell_class) do
    Class.new do
      include Core::Views::ViteManifest
    end
  end
  let(:shell) { shell_class.new }
  let(:nonce) { 'n0nce' }

  # Two entries sharing a chunk graph, one lazy route, one stylesheet, one font.
  let(:manifest) do
    {
      'main.ts' => {
        'file' => 'assets/main.AAAA.js',
        'isEntry' => true,
        'imports' => ['_vue-BBBB.js', '_i18n-CCCC.js'],
        'dynamicImports' => ['apps/secret/support/Help.vue'],
      },
      'admin.ts' => {
        'file' => 'assets/admin.DDDD.js',
        'isEntry' => true,
        'imports' => ['_vue-BBBB.js'],
      },
      '_vue-BBBB.js' => { 'file' => 'assets/vue-BBBB.js', 'imports' => ['_runtime-EEEE.js'] },
      '_i18n-CCCC.js' => { 'file' => 'assets/i18n-CCCC.js', 'imports' => ['_runtime-EEEE.js'] },
      '_runtime-EEEE.js' => { 'file' => 'assets/runtime-EEEE.js' },
      'apps/secret/support/Help.vue' => { 'file' => 'assets/Help-FFFF.js', 'isDynamicEntry' => true },
      'style.css' => { 'file' => 'assets/style.GGGG.css' },
      'assets/fonts/Inter.woff2' => { 'file' => 'assets/Inter.HHHH.woff2' },
    }
  end

  # A before hook, not an around hook: stub_const needs rspec-mocks' per-example
  # lifecycle, which is set up after around hooks have started.
  let(:public_dir) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(public_dir, 'dist', '.vite'))
    File.write(File.join(public_dir, 'dist', '.vite', 'manifest.json'), JSON.generate(manifest))
    stub_const('Core::Views::ViteManifest::PUBLIC_DIR', public_dir)
  end

  after { FileUtils.remove_entry(public_dir) }

  def tags(html)
    html.lines.map(&:strip)
  end

  def preloads(html)
    tags(html).grep(/rel="modulepreload"/)
  end

  describe '#vite_assets in production' do
    subject(:html) { shell.vite_assets(nonce: nonce, development: false, entry: 'main.ts') }

    it 'opens with the csp-nonce meta tag, then the nonced entry script' do
      expect(tags(html).first).to eq(%(<meta property="csp-nonce" nonce="n0nce">))
      expect(tags(html)[1]).to eq(
        %(<script type="module" nonce="n0nce" src="/dist/assets/main.AAAA.js"></script>),
      )
    end

    it 'preloads the static import graph once each, with the nonce' do
      expect(preloads(html)).to eq(
        [
          %(<link rel="modulepreload" nonce="n0nce" href="/dist/assets/vue-BBBB.js">),
          %(<link rel="modulepreload" nonce="n0nce" href="/dist/assets/runtime-EEEE.js">),
          %(<link rel="modulepreload" nonce="n0nce" href="/dist/assets/i18n-CCCC.js">),
        ],
      )
    end

    it 'leaves dynamic imports to the runtime preload helper' do
      expect(html).not_to include('Help-FFFF.js')
    end

    it 'links the shared stylesheet and preloads fonts with the nonce' do
      expect(html).to include(
        %(<link rel="stylesheet" nonce="n0nce" href="/dist/assets/style.GGGG.css">),
      )
      expect(html).to include(
        %(<link rel="preload" nonce="n0nce" href="/dist/assets/Inter.HHHH.woff2" as="font" type="font/woff2" crossorigin>),
      )
    end

    it 'resolves the admin entry from the same manifest' do
      admin = shell.vite_assets(nonce: nonce, development: false, entry: 'admin.ts')

      expect(admin).to include('src="/dist/assets/admin.DDDD.js"')
      expect(preloads(admin).length).to eq(2)
      expect(admin).not_to include('main.AAAA.js')
    end

    it 'warns from a nonced script instead of raising for an unknown entry' do
      expect(shell.vite_assets(nonce: nonce, development: false, entry: 'nope.ts')).to eq(
        %(<script nonce="n0nce">console.warn("Entry 'nope.ts' not found in Vite manifest")</script>),
      )
    end
  end
end
