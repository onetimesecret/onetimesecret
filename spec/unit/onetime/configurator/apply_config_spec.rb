# tests/unit/ruby/rspec/onetime/config/apply_config_spec.rb

require_relative '../../../spec_helper'
require 'onetime/models'

RSpec.describe Onetime do
  describe '.apply_config' do
    let(:original_config) do
      {
        site: {
          host: 'localhost',
          ssl: false,
          interface: {
            ui: {
              enabled: true,
              header: {
                enabled: true,
                branding: {
                  logo: {
                    url: '/img/logo.png',
                    alt: 'OneTime Secret',
                    href: '/'
                  },
                  site_name: 'OneTime Secret'
                }
              }
            },
            api: {
              enabled: true
            }
          },
          secret_options: {
            default_ttl: 3600,
            ttl_options: [300, 3600, 86400]
          }
        },
        mail: {
          truemail: {
            verifier_email: 'verifier@example.com',
            verifier_domain: 'example.com',
            default_validation_type: 'mx'
          }
        },
        limits: {
          create_secret: 250,
          send_feedback: 10,
          get_page: 100
        },
        diagnostics: {
          enabled: true,
          sentry: {
            backend: {
              dsn: 'https://backend@sentry.example.com/1'
            },
            frontend: {
              dsn: 'https://frontend@sentry.example.com/2'
            }
          }
        }
      }
    end

    let(:override_config) do
      {
        site: {
          interface: {
            ui: {
              enabled: false,
              header: {
                branding: {
                  site_name: 'Custom Company'
                }
              }
            }
          },
          secret_options: {
            default_ttl: 7200
          }
        },
        limits: {
          create_secret: 500
        }
      }
    end

    before do
      # Mock OT.conf to return our test configuration
      allow(OT).to receive(:conf).and_return(original_config)
    end

    context 'with valid configurations' do
      it 'merges override config into existing OT.conf' do
        expect(OT).to receive(:replace_config!).with(hash_including(
          'site' => hash_including(
            'interface' => hash_including(
              'ui' => hash_including(
                'enabled' => false
              )
            ),
            'secret_options' => hash_including(
              'default_ttl' => 7200
            )
          ),
          'limits' => hash_including(
            'create_secret' => 500
          )
        ))

        Onetime.apply_config(override_config)
      end

      it 'preserves original values not overridden' do
        expect(OT).to receive(:replace_config!) do |runtime_config|
          expect(runtime_config['site']['interface']['api']['enabled']).to eq(true)
          expect(runtime_config['mail']['truemail']['verifier_email']).to eq('verifier@example.com')
          expect(runtime_config['limits']['send_feedback']).to eq(10)
        end

        Onetime.apply_config(override_config)
      end

      it 'handles nested hash merging correctly' do
        nested_override = {
          diagnostics: {
            sentry: {
              backend: {
                dsn: 'https://new-backend@sentry.example.com/1',
                sampleRate: 0.5
              }
            }
          }
        }

        expect(OT).to receive(:replace_config!) do |runtime_config|
          expect(runtime_config['diagnostics']['enabled']).to eq(true)
          expect(runtime_config['diagnostics']['sentry']['backend']['dsn']).to eq('https://new-backend@sentry.example.com/1')
          expect(runtime_config['diagnostics']['sentry']['backend']['sampleRate']).to eq(0.5)
          expect(runtime_config['diagnostics']['sentry']['frontend']['dsn']).to eq('https://frontend@sentry.example.com/2')
        end

        Onetime.apply_config(nested_override)
      end
    end

    context 'with edge cases' do
      it 'handles nil override config' do
        # Since deep_merge normalizes keys to strings, we need to expect the normalized version
        normalized_original = OT::Utils.deep_merge({}, original_config)
        expect(OT).to receive(:replace_config!).with(normalized_original)
        Onetime.apply_config(nil)
      end

      it 'handles empty override config' do
        # Since deep_merge normalizes keys to strings, we need to expect the normalized version
        normalized_original = OT::Utils.deep_merge({}, original_config)
        expect(OT).to receive(:replace_config!).with(normalized_original)
        Onetime.apply_config({})
      end

      it 'preserves original values when override contains nil values' do
        override_with_nils = {
          site: {
            interface: {
              ui: {
                enabled: nil
              }
            }
          },
          mail: nil
        }

        expect(OT).to receive(:replace_config!) do |runtime_config|
          # nil values in override should preserve original values
          expect(runtime_config['site']['interface']['ui']['enabled']).to eq(true)
          # Convert original config mail section to string keys for comparison
          original_mail_normalized = OT::Utils.deep_merge({}, { mail: original_config[:mail] })['mail']
          expect(runtime_config['mail']).to eq(original_mail_normalized)
        end

        Onetime.apply_config(override_with_nils)
      end

      it 'handles nil OT.conf gracefully' do
        allow(OT).to receive(:conf).and_return(nil)

        # Since deep_merge normalizes keys to strings, we need to expect the normalized version
        normalized_override = OT::Utils.deep_merge({}, override_config)
        expect(OT).to receive(:replace_config!).with(normalized_override)
        Onetime.apply_config(override_config)
      end

      it 'does not modify the original OT.conf or override config' do
        original_override = override_config.dup
        original_ot_conf = original_config.dup

        Onetime.apply_config(override_config)

        expect(override_config).to eq(original_override)
        expect(OT.conf).to eq(original_ot_conf)
      end
    end

    context 'with complete override scenarios' do
      it 'correctly applies multiple sections' do
        complete_override = {
          site: {
            host: 'custom.example.com',
            interface: {
              ui: {
                enabled: false
              }
            },
            secret_options: {
              default_ttl: 7200
            }
          },
          mail: {
            truemail: {
              verifier_email: 'custom@example.com',
              default_validation_type: 'regex'
            }
          },
          limits: {
            create_secret: 1000,
            send_feedback: 50
          },
          diagnostics: {
            enabled: false
          }
        }

        expect(OT).to receive(:replace_config!) do |runtime_config|
          expect(runtime_config['site']['host']).to eq('custom.example.com')
          expect(runtime_config['site']['interface']['ui']['enabled']).to eq(false)
          expect(runtime_config['site']['secret_options']['default_ttl']).to eq(7200)
          expect(runtime_config['mail']['truemail']['verifier_email']).to eq('custom@example.com')
          expect(runtime_config['mail']['truemail']['default_validation_type']).to eq('regex')
          expect(runtime_config['limits']['create_secret']).to eq(1000)
          expect(runtime_config['limits']['send_feedback']).to eq(50)
          expect(runtime_config['diagnostics']['enabled']).to eq(false)
        end

        Onetime.apply_config(complete_override)
      end
    end
  end
end
