# lib/onetime/middleware/startup_readiness.rb

module Onetime
  module Middleware
    class StartupReadiness

      def initialize(app)
        @app = app
      end

      def call(env)
        if Onetime.ready?
          @app.call(env)
        else
          [503, {'Content-Type' => 'text/html'}, [STARTUP_HTML]]
        end
      end

      STARTUP_HTML = <<~HTML
        <html>
          <head>
            <style>
              body {
                background-color: #adb5bd;
                color: #000000;
                padding: 1rem;
                border-radius: 0.25rem;
                text-align: center;
                padding: 20px;
              }
            </style>
            <script>
              document.addEventListener('DOMContentLoaded', function() {
                const fonts = [
                  'Comic Sans MS', 'Papyrus', 'Impact', 'Brush Script MT',
                  'Courier New', 'Monaco', 'Chalkduster', 'Copperplate',
                  'Lucida Console', 'Futura', 'Bebas Neue', 'Creepster',
                  'Chiller', 'Jokerman', 'cursive', 'fantasy', 'monospace'
                ];
                const randomFont = fonts[Math.floor(Math.random() * fonts.length)];
                document.body.style.fontFamily = randomFont;
              });
            </script>
          </head>
          <body>
            <h2>Configuration Incomplete</h2>
            <p>Server booted successfully but static configuration is missing.</p>
            <p>Please check server logs for details.</p>
          </body>
        </html>
      HTML

    end
  end
end
