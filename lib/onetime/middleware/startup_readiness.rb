# lib/onetime/middleware/startup_readiness.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # Onetime::Middleware::StartupReadiness
    #
    # Shows a friendly error message if a request is received before the
    # application is ready. This can happen when there was a problem
    # loading the configuration for example. The ruby application
    # will be running but return a 503 status.
    #
    # Returns JSON based on the response type, otherwise HTML.
    #
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Layout/LineLength
    class StartupReadiness
      # Basic translations for startup message
      TRANSLATIONS = {
        en: {
          title: 'Configuration Incomplete',
          message1: 'Server booted successfully but static configuration is missing.',
          message2: 'Please check server logs for details.',
        },
        es: {
          title: 'Configuración Incompleta',
          message1: 'El servidor arrancó correctamente pero falta la configuración estática.',
          message2: 'Por favor, revise los registros del servidor para más detalles.',
        },
        fr: {
          title: 'Configuration Incomplète',
          message1: 'Le serveur a démarré avec succès mais la configuration statique est manquante.',
          message2: 'Veuillez consulter les journaux du serveur pour plus de détails.',
        },
        ta: {
          title: 'முழு பயன்பாடு இல்லை',
          message1: 'சேவையகம் வெற்றிகரமாக துவங்கியது ஆனால் நிலையான கட்டமைப்பு காணவில்லை.',
          message2: 'விவரங்களுக்கு சேவையக பதிவுகளை சரிபார்க்கவும்.',
        },
        ba: {
          title: 'Конфигурация неполная',
          message1: 'Сервер успешно запущен, но отсутствует статическая конфигурация.',
          message2: 'Пожалуйста, проверьте журналы сервера для получения подробностей.',
        },
        bg: {
          title: 'Непълна конфигурация',
          message1: 'Сървърът е успешно стартиран, но липсва статична конфигурация.',
          message2: 'Моля, проверете журнала на сървъра за подробности.',
        },
        cs: {
          title: 'Nepřípravený server',
          message1: 'Server byl úspěšně spuštěn, ale chybí statická konfigurace.',
          message2: 'Zkontrolujte protokoly serveru pro další informace.',
        },
        de: {
          title: 'Konfiguration unvollständig',
          message1: 'Der Server wurde erfolgreich gestartet, aber die statische Konfiguration fehlt.',
          message2: 'Bitte überprüfen Sie die Serverprotokolle für Details.',
        },
        de_AT: {
          title: 'Konfiguration nicht vollständig',
          message1: 'Der Server wurde erfolgreich gestartet, jedoch fehlt die statische Konfiguration.',
          message2: 'Wir ersuchen Sie, die Serverprotokolle für nähere Informationen zu konsultieren.',
        },
        nl: {
          title: 'Configuratie onvolledig',
          message1: 'De server is succesvol opgestart, maar de statische configuratie ontbreekt.',
          message2: 'Controleer de serverlogboeken voor details.',
        },
        da: {
          title: 'Konfiguration ufuldstændig',
          message1: 'Serveren startede med succes, men den statiske konfiguration mangler.',
          message2: 'Tjek serverlogfiler for detaljer.',
        },
        uk: {
          title: 'Конфігурація неповна',
          message1: 'Сервер успішно запущено, але статична конфігурація відсутня.',
          message2: 'Будь ласка, перевірте журнали сервера для отримання деталей.',
        },
        ko: {
          title: '구성이 불완전함',
          message1: '서버가 성공적으로 부팅되었지만 정적 구성이 누락되었습니다.',
          message2: '자세한 내용은 서버 로그를 확인하세요.',
        },
        zh: {
          title: '配置不完整',
          message1: '服务器成功启动，但缺少静态配置。',
          message2: '请查看服务器日志以获取详细信息。',
        },
        ja: {
          title: '設定が不完全',
          message1: 'サーバーが正常に起動しましたが、静的設定が欠落しています。',
          message2: '詳細はサーバーログを確認してください。',
        },
      }

      def initialize(app, response_type: :auto, translations: nil)
        @app           = app
        @response_type = response_type
        @translations  = translations || self.class.translations || TRANSLATIONS
      end

      def call(env)
        return @app.call(env) if Onetime.ready?

        lang_code = parse_accept_language(env)

        if should_return_json?(env)
          json_response(lang_code)
        else
          html_response(lang_code)
        end
      end

      class << self
        attr_reader :default_response_type, :translations

        def response_type(type)
          OT.ld("[middleware] setting response type to #{type}")
          self.default_response_type = type
        end

        def use_translations(translations)
          self.translations = translations
        end
      end

      private

      def should_return_json?(env)
        case @response_type
        when :json
          true
        when :html
          false
        when :auto
          detect_json_api?(env)
        else
          if respond_to?(:custom_response_type_check?, true)
            # Allows subclasses to override with custom logic
            custom_response_type_check?(env)
          else
            false # default to HTML response
          end
        end
      end

      def detect_json_api?(env)
        # Access the application's mount point to make an educated guess
        mount_point = env['SCRIPT_NAME']
        mount_point.start_with?('/api')
      end

      def json_response(lang_code)
        response_body = {
          status: 'not_ready',
          error: {
            code: 'CONFIGURATION_INCOMPLETE',
            title: @translations[lang_code][:title],
            message: @translations[lang_code][:message1],
            details: @translations[lang_code][:message2],
          },
          timestamp: Familia.now.utc.iso8601,
        }

        [503,
         { 'content-type' => 'application/json; charset=utf-8' },
         [response_body.to_json]]
      end

      def html_response(lang_code)
        html = build_html_response(lang_code)

        [503,
         { 'content-type' => 'text/html; charset=utf-8' },
         [html.encode('UTF-8')]]
      end

      def build_html_response(lang_code)
        <<~HTML
          <!DOCTYPE html>
          <html lang="#{lang_code}" class="light">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>#{@translations[lang_code][:title]}</title>
              #{html_styles}
              #{html_scripts(lang_code)}
            </head>
            <body>
              <div class="container">
                <h2 id="title">#{@translations[lang_code][:title]}</h2>
                <p id="message1">#{@translations[lang_code][:message1]}</p>
                <p id="message2">#{@translations[lang_code][:message2]}</p>
              </div>
            </body>
          </html>
        HTML
      end

      def html_styles
        <<~CSS
          <style>
            :root {
              --bg-color: #ffffff;
              --text-color: rgb(17 24 39);
            }

            html.dark {
              --bg-color: rgb(17 24 39);
              --text-color: #ffffff;
            }

            body {
              background-color: var(--bg-color);
              color: var(--text-color);
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              margin: 0;
              padding: 20px;
              transition: background-color 0.3s ease, color 0.3s ease;
            }

            .container {
              max-width: 600px;
              margin: 0 auto;
              text-align: center;
              padding: 2rem;
            }

            h2 {
              margin-bottom: 1rem;
              font-size: 1.5rem;
            }

            p {
              margin-bottom: 0.5rem;
              line-height: 1.5;
            }
          </style>
        CSS
      end

      def html_scripts(lang_code)
        <<~JAVASCRIPT
          <script>
            // Run immediately to avoid FOUC
            (function() {
              // Check for dark mode preference
              var isDarkMode = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;

              // Apply class immediately
              if (isDarkMode) {
                document.documentElement.classList.remove('light');
                document.documentElement.classList.add('dark');
              }
            })();

            // Set up proper theme change detection
            document.addEventListener('DOMContentLoaded', function() {
              var darkModeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
              var htmlElement = document.documentElement;

              // Function to update theme
              function updateTheme(isDark) {
                if (isDark) {
                  htmlElement.classList.remove('light');
                  htmlElement.classList.add('dark');
                } else {
                  htmlElement.classList.remove('dark');
                  htmlElement.classList.add('light');
                }
              }

              // Set up cross-browser compatible event listener
              try {
                // Modern API (addEventListener)
                darkModeMediaQuery.addEventListener('change', function(e) {
                  updateTheme(e.matches);
                });
              } catch (e1) {
                try {
                  // Fallback for Safari 13, iOS 13
                  darkModeMediaQuery.addListener(function(e) {
                    updateTheme(e.matches);
                  });
                } catch (e2) {
                  console.error('Could not set up theme change detection', e2);
                }
              }

              // Log for debugging
              console.log('Theme detection initialized. Current mode:',
                darkModeMediaQuery.matches ? 'dark' : 'light');
            });
          </script>
          <script>
            // All available languages
            const translations = #{TRANSLATIONS.to_json};
            const languageCodes = Object.keys(translations);

            // Initialize with the user's language
            let currentLang = "#{lang_code}";

            // Set up random font on load
            document.addEventListener('DOMContentLoaded', function() {

              const fonts = [
                'Comic Sans MS', 'Papyrus', 'Impact', 'Brush Script MT',
                'Courier New', 'Monaco', 'Chalkduster', 'Copperplate',
                'Lucida Console', 'Futura', 'Bebas Neue', 'Creepster',
                'Chiller', 'Jokerman', 'cursive', 'fantasy', 'monospace'
              ];
              const randomFont = fonts[Math.floor(Math.random() * fonts.length)];
              document.body.style.fontFamily = randomFont;

              // Set up click handler for language switching by attaching
              // to document directly (not document.body)
              document.addEventListener('click', function(event) {

                // Get a random language that's different from current
                let newLang;
                do {
                  const randomIndex = Math.floor(Math.random() * languageCodes.length);
                  newLang = languageCodes[randomIndex];
                } while (newLang === currentLang && languageCodes.length > 1);

                currentLang = newLang;

                // Update the text content
                document.getElementById('title').textContent = translations[newLang].title;
                document.getElementById('message1').textContent = translations[newLang].message1;
                document.getElementById('message2').textContent = translations[newLang].message2;

                // Also change the font when language changes
                const newRandomFont = fonts[Math.floor(Math.random() * fonts.length)];
                document.body.style.fontFamily = newRandomFont;
              });
            });
          </script>
          <script>
            /*
            console.log('Script loading...');
            console.log('Translations:', typeof translations, translations);
            console.log('Current lang:', currentLang);
            console.log('Language codes:', languageCodes); */
          </script>
        JAVASCRIPT
      end

      def parse_accept_language(env)
        accept_language = env['HTTP_ACCEPT_LANGUAGE'] || ''
        return :en if accept_language.empty?

        lang = accept_language.split(',').first&.split(';')&.first
        return :en unless lang

        # Handle special cases
        return :de_AT if lang.downcase == 'de-at'

        base_lang = lang.split('-').first&.downcase&.to_sym
        @translations.key?(base_lang) ? base_lang : :en
      end
    end
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Layout/LineLength
  end
end
