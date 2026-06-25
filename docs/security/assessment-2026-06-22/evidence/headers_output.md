2026-06-22 17:25:12.166913 [31mE[0m [27527:2456 class_methods.rb:278] [31mBoot[0m -- [i18n] Missing locale file: /home/user/onetimesecret/generated/locales/en.json
2026-06-22 17:25:12.194514 [31mE[0m [27527:2456 class_methods.rb:278] [31mBoot[0m -- [init] No JSON locale files found in generated/locales/*.json
2026-06-22 17:25:12.199156 [36mI[0m [27527:2456] [36mAuth[0m -- ╭────────────────────────────────────────────────────╮
2026-06-22 17:25:12.199224 [36mI[0m [27527:2456] [36mAuth[0m -- │ AUTHENTICATION MODE: Simple (Core handles /auth/*) │
2026-06-22 17:25:12.199228 [36mI[0m [27527:2456] [36mAuth[0m -- ╰────────────────────────────────────────────────────╯
2026-06-22 17:25:13.316487 [36mI[0m [27527:2456] [36mHTTP[0m -- [middleware] ViteProxy: Using frontend proxy for /dist to http://localhost:5173
2026-06-22 17:25:13.330730 [36mI[0m [27527:2456] [36mHTTP[0m -- {"method":"GET","path":"/api/v2/status","status":200,"duration_ms":0.97}

=== GET /api/v2/status  -> HTTP 200 ===
  content-security-policy:       <ABSENT>
  x-frame-options:               <ABSENT>
  strict-transport-security:     <ABSENT>
  x-content-type-options:        nosniff
  x-xss-protection:              1; mode=block
  referrer-policy:               strict-origin-when-cross-origin
  cross-origin-opener-policy:    <ABSENT>
  access-control-allow-origin:   <ABSENT>
  set-cookie:                    onetime.session=4bb99fb210578051fa5375efa1fe54de305e86ad03492a274f9dedc6ed1779cf
2026-06-22 17:25:13.334528 [31mE[0m [27527:2456 lint.rb:159] [31mHTTP[0m -- Request processing failed -- {url: "http://localhost:3000/", method: "GET", ip: "127.0.0.0"} -- Exception: [31mRack::Lint::LintError: env variable HTTP_USER_AGENT has non-string value nil[0m
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/lint.rb:159:in 'block in Rack::Lint::Wrapper#check_environment'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/lint.rb:155:in 'Hash#each'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/lint.rb:155:in 'Rack::Lint::Wrapper#check_environment'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/lint.rb:90:in 'Rack::Lint::Wrapper#response'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/lint.rb:16:in 'Rack::Lint#call'
/home/user/onetimesecret/apps/web/core/middleware/vite_proxy.rb:43:in 'Core::Middleware::ViteProxy#call'
/home/user/onetimesecret/apps/web/core/middleware/error_handling.rb:27:in 'Core::Middleware::ErrorHandling#call'
/home/user/onetimesecret/apps/web/core/middleware/request_setup.rb:29:in 'Core::Middleware::RequestSetup#call'
/home/user/onetimesecret/lib/onetime/middleware/security.rb:85:in 'block (2 levels) in Onetime::Middleware::Security#setup_security_middleware'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-protection-4.2.1/lib/rack/protection/base.rb:53:in 'Rack::Protection::Base#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-utf8_sanitizer-1.11.1/lib/rack/utf8_sanitizer.rb:34:in 'Rack::UTF8Sanitizer#call'
/home/user/onetimesecret/lib/onetime/middleware/security.rb:52:in 'Onetime::Middleware::Security#call'
/home/user/onetimesecret/lib/onetime/middleware/csrf_response_header.rb:30:in 'Onetime::Middleware::CsrfResponseHeader#call'
/home/user/onetimesecret/lib/onetime/application/request_logger.rb:36:in 'Onetime::Application::RequestLogger#call'
/home/user/onetimesecret/lib/onetime/middleware/domain_strategy.rb:146:in 'Onetime::Middleware::DomainStrategy#call'
/home/user/onetimesecret/lib/middleware/i18n_locale.rb:48:in 'block in Middleware::I18nLocale#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/i18n-1.14.8/lib/i18n.rb:354:in 'I18n::Base#with_locale'
/home/user/onetimesecret/lib/middleware/i18n_locale.rb:47:in 'Middleware::I18nLocale#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/otto-2.3.1/lib/otto/locale/middleware.rb:62:in 'Otto::Locale::Middleware#call'
/home/user/onetimesecret/lib/onetime/middleware/identity_resolution.rb:70:in 'Onetime::Middleware::IdentityResolution#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-session-2.1.2/lib/rack/session/abstract/id.rb:274:in 'Rack::Session::Abstract::Persisted#context'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-session-2.1.2/lib/rack/session/abstract/id.rb:268:in 'Rack::Session::Abstract::Persisted#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-parser-0.7.0/lib/rack/parser.rb:24:in 'Rack::Parser#call'
/home/user/onetimesecret/lib/onetime/middleware/normalize_content_type.rb:57:in 'Onetime::Middleware::NormalizeContentType#call'
/home/user/onetimesecret/lib/middleware/request_id.rb:83:in 'Rack::RequestId#call'
/home/user/onetimesecret/lib/middleware/detect_host.rb:194:in 'Rack::DetectHost#call'
/home/user/onetimesecret/lib/onetime/middleware/startup_readiness.rb:105:in 'Onetime::Middleware::StartupReadiness#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/content_length.rb:20:in 'Rack::ContentLength#call'
/home/user/onetimesecret/lib/onetime/middleware/health_access_control.rb:33:in 'Onetime::Middleware::HealthAccessControl#call'
/home/user/onetimesecret/lib/onetime/middleware/ip_ban.rb:35:in 'Onetime::Middleware::IPBan#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/otto-2.3.1/lib/otto/security/middleware/ip_privacy_middleware.rb:67:in 'Otto::Security::Middleware::IPPrivacyMiddleware#call'
/home/user/onetimesecret/lib/onetime/application/base.rb:102:in 'Onetime::Application::Base#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/urlmap.rb:76:in 'block in Rack::URLMap#call'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/urlmap.rb:60:in 'Array#each'
/opt/rbenv/versions/3.4.9/lib/ruby/gems/3.4.0/gems/rack-3.2.6/lib/rack/urlmap.rb:60:in 'Rack::URLMap#call'
/home/user/security-assessment/poc/headers_check.rb:29:in 'block in <main>'
/home/user/security-assessment/poc/headers_check.rb:27:in 'Array#each'
/home/user/security-assessment/poc/headers_check.rb:27:in '<main>'
2026-06-22 17:25:13.395495 [31mE[0m [27527:2456 request_logger.rb:50] [31mHTTP[0m -- {"method":"GET","path":"/","status":500,"duration_ms":61.262}

=== GET /  -> HTTP 500 ===
  content-security-policy:       <ABSENT>
  x-frame-options:               <ABSENT>
  strict-transport-security:     <ABSENT>
  x-content-type-options:        <ABSENT>
  x-xss-protection:              <ABSENT>
  referrer-policy:               <ABSENT>
  cross-origin-opener-policy:    <ABSENT>
  access-control-allow-origin:   <ABSENT>
  set-cookie:                    onetime.session=0e39d7a3e9b594c689bd9a9d261b930eca64668f55659be9b38bb1a7f5140a77
