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

  # Two entries sharing a chunk graph, one lazy route, one stylesheet, and the
  # font files Vite emits for the four @font-face blocks (woff2 + woff each).
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
      'assets/fonts/zs/ZillaSlab-Regular.woff2' => { 'file' => 'assets/ZillaSlab-Regular.HHHH.woff2' },
      'assets/fonts/zs/ZillaSlab-Regular.woff' => { 'file' => 'assets/ZillaSlab-Regular.IIII.woff' },
      'assets/fonts/zs/ZillaSlab-Bold.woff2' => { 'file' => 'assets/ZillaSlab-Bold.JJJJ.woff2' },
      'assets/fonts/zs/ZillaSlab-Bold.woff' => { 'file' => 'assets/ZillaSlab-Bold.KKKK.woff' },
      'assets/fonts/zs/ZillaSlab-Italic.woff2' => { 'file' => 'assets/ZillaSlab-Italic.LLLL.woff2' },
      'assets/fonts/zs/ZillaSlab-BoldItalic.woff2' => { 'file' => 'assets/ZillaSlab-BoldItalic.MMMM.woff2' },
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

    it 'links the shared stylesheet and preloads the upright woff2 faces with the nonce' do
      expect(html).to include(
        %(<link rel="stylesheet" nonce="n0nce" href="/dist/assets/style.GGGG.css">),
      )
      expect(tags(html).grep(/as="font"/)).to eq(
        [
          %(<link rel="preload" nonce="n0nce" href="/dist/assets/ZillaSlab-Regular.HHHH.woff2" as="font" type="font/woff2" crossorigin>),
          %(<link rel="preload" nonce="n0nce" href="/dist/assets/ZillaSlab-Bold.JJJJ.woff2" as="font" type="font/woff2" crossorigin>),
        ],
      )
    end

    it 'leaves the italic faces and the woff fallbacks to @font-face' do
      expect(html).not_to include('ZillaSlab-Italic')
      expect(html).not_to include('ZillaSlab-BoldItalic')
      expect(html).not_to include('.woff"')
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

  # PRELOADED_FONTS names the woff2 files of the upright Regular (400) and
  # Bold (700) faces by their root-relative source path. The stylesheet is the
  # other half of that contract: if a face is renamed or moved there and the
  # regex is not updated, the preload silently disappears. Read the real
  # stylesheet and check both directions.
  describe 'PRELOADED_FONTS against src/assets/style.css' do
    let(:faces) do
      css = File.read(File.join(Onetime::HOME, 'src', 'assets', 'style.css'))
      css.scan(/@font-face\s*\{(.*?)\}/m).map(&:first).map do |block|
        {
          weight: block[/font-weight:\s*(\d+)/, 1].to_i,
          style: block[/font-style:\s*(\w+)/, 1],
          # url('./fonts/zs/X.woff2') relative to src/ is the manifest key assets/fonts/zs/X.woff2
          woff2: block[%r{url\('\./(fonts/[^']+\.woff2)'\)}, 1]&.then { |path| "assets/#{path}" },
        }
      end
    end

    it 'preloads exactly the upright Regular and Bold faces the stylesheet declares', :aggregate_failures do
      upright = faces.select { |f| f[:style] == 'normal' && [400, 700].include?(f[:weight]) }
      others  = faces - upright

      expect(upright.map { |f| f[:woff2] }).to all(match(described_class::PRELOADED_FONTS))
      expect(others.map { |f| f[:woff2] }).to all(satisfy { |key| !key.match?(described_class::PRELOADED_FONTS) })
      expect(upright.length).to eq(2)
    end
  end
end
