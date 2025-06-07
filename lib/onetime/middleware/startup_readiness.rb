# lib/onetime/middleware/startup_readiness.rb

module Onetime
  module Middleware
    class StartupReadiness
      # Basic translations for startup message
      TRANSLATIONS = {
        en: {
          title: "Configuration Incomplete",
          message1: "Server booted successfully but static configuration is missing.",
          message2: "Please check server logs for details.",
        },
        es: {
          title: "Configuración Incompleta",
          message1: "El servidor arrancó correctamente pero los componentes de configuración requeridos aún no están completamente cargados.",
          message2: "Por favor, actualice en un momento o revise los registros del servidor para más detalles.",
        },
        fr: {
          title: "Configuration Incomplète",
          message1: "Le serveur a démarré avec succès mais les composants de configuration requis ne sont pas encore complètement chargés.",
          message2: "Veuillez rafraîchir dans un instant ou consulter les journaux du serveur pour plus de détails.",
        },
        ta: {
          title: "முழு பயன்பாடு இல்லை",
          message1: "தரவு வெளியே முடிவடைந்தது, இன்று மேலும் பயன்பாடுகள் பதிவு செய்யப்படும்.",
          message2: "தரவு வெளியே முடிவடைந்தது, இன்று மேலும் பயன்பாடுகள் பதிவு செய்யப்படும்.",
        },
        ba: {
          title: "Конфигурация неполная",
          message1: "Сервер успешно запущен, но необходимые компоненты конфигурации еще не полностью загружены.",
          message2: "Пожалуйста, обновите страницу через несколько секунд или проверьте журналы сервера для получения дополнительной информации.",
        },
        bg: {
          title: "Непълна конфигурация",
          message1: "Сървърът е успешно стартиран, но необходимите компоненти за конфигурация все още не са напълно заредени.",
          message2: "Моля, актуализирайте страницата след няколко секунди или проверете журнала на сървъра за допълнителна информация.",
        },
        cs: {
          title: "Nepřípravený server",
          message1: "Server byl úspěšně spuštěn, ale potřebné komponenty pro nastavení ještě nejsou plně načteny.",
          message2: "Prosím, aktualizujte stránku za několik sekund nebo zkontrolujte serverový protokol pro další informace.",
        },
        de: {
          title: "Konfiguration unvollständig",
          message1: "Der Server wurde erfolgreich gestartet, aber die erforderlichen Konfigurationskomponenten sind noch nicht vollständig geladen.",
          message2: "Bitte aktualisieren Sie in einem Moment oder überprüfen Sie die Serverprotokolle für Details.",
        },
        de_AT: {
          title: "Konfiguration nicht vollständig",
          message1: "Der Server wurde erfolgreich gestartet, jedoch sind die erforderlichen Konfigurationskomponenten noch nicht zur Gänze geladen.",
          message2: "Wir ersuchen Sie, die Seite in Kürze erneut zu laden oder die Serverprotokolle für nähere Informationen zu konsultieren.",
        },
        nl: {
          title: "Configuratie onvolledig",
          message1: "De server is succesvol opgestart, maar de vereiste configuratiecomponenten zijn nog niet volledig geladen.",
          message2: "Vernieuw over een moment of controleer de serverlogboeken voor details.",
        },

        da: {
          title: "Konfiguration ufuldstændig",
          message1: "Serveren startede med succes, men de nødvendige konfigurationskomponenter er endnu ikke fuldt indlæst.",
          message2: "Opdater om et øjeblik eller tjek serverlogfiler for detaljer.",
        },
        uk: {
          title: "Конфігурація неповна",
          message1: "Сервер успішно запущено, але необхідні компоненти конфігурації ще не повністю завантажені.",
          message2: "Будь ласка, оновіть сторінку за мить або перевірте журнали сервера для отримання деталей.",
        },
        ko: {
          title: "구성이 불완전함",
          message1: "서버가 성공적으로 부팅되었지만 필요한 구성 요소가 아직 완전히 로드되지 않았습니다.",
          message2: "잠시 후 새로고침하거나 서버 로그에서 자세한 내용을 확인하세요.",
        },
        zh: {
          title: "配置不完整",
          message1: "服务器成功启动，但所需的配置组件尚未完全加载。",
          message2: "请稍后刷新或查看服务器日志以获取详细信息。",
        },
        ja: {
          title: "設定が不完全",
          message1: "サーバーが正常に起動しましたが、必要なコンポーネントがまだ完全にロードされていません。",
          message2: "しばらくしてリロードするか、サーバーログを確認してください。",
        },
      }

      def initialize(app)
        @app = app
      end

      def call(env)
        if Onetime.ready?
          @app.call(env)
        else
          # Get preferred language from Accept-Language header
          accept_language = env['HTTP_ACCEPT_LANGUAGE'] || ''
          lang_code = parse_accept_language(accept_language)

          html = <<~HTML
            <html lang="#{lang_code}" class="light">
              <head>
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
                  padding: 1rem;
                  border-radius: 0.25rem;
                  text-align: center;
                  padding: 20px;
                  cursor: pointer;
                  transition: background-color 0.3s ease, color 0.3s ease;
                }
              </style>
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

                    // Set up click handler for language switching
                    document.body.addEventListener('click', function() {
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
              </head>
              <body>
                <h2 id="title">#{TRANSLATIONS[lang_code][:title]}</h2>
                <p id="message1">#{TRANSLATIONS[lang_code][:message1]}</p>
                <p id="message2">#{TRANSLATIONS[lang_code][:message2]}</p>
              </body>
            </html>
          HTML

          [503, {'Content-Type' => 'text/html; charset=utf-8'}, [html.encode('UTF-8')]]
        end
      end

      private

      # Parse Accept-Language header to get preferred language code
      def parse_accept_language(accept_language)
        return :en if accept_language.empty?

        # Extract language code from Accept-Language header (e.g., "en-US,en;q=0.9")
        lang = accept_language.split(',').first.split(';').first

        # Handle special case for de_AT (Austrian German)
        if lang.downcase == 'de-at'
          return :de_AT
        end

        # Extract base language code
        base_lang = lang.split('-').first.downcase.to_sym

        # Return language if we have a translation, otherwise fall back to English
        TRANSLATIONS.key?(base_lang) ? base_lang : :en
      end
    end
  end
end


__END__
{'Content-Type' => 'text/html; charset=utf-8'},
[html.encode('UTF-8')]]
