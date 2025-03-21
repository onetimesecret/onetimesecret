# frozen_string_literal: true

module V1::Mixins

  # Module containing helper methods for session-related functionality
  module SessionHelpers

    # @return [Boolean] true if the user agent is Opera
    def opera?() @agent.to_s =~ /opera|opr/i end
    def opera?()            @agent.to_s =~ /opera|opr/i                      end
    def firefox?()          @agent.to_s =~ /firefox|fxios/i                  end
    def chrome?()           @agent.to_s =~ /chrome|crios/i                   end
    def safari?()           @agent.to_s =~ /safari/i && !chrome?             end
    def edge?()             @agent.to_s =~ /edge|edg/i                       end
    def konqueror?()        @agent.to_s =~ /konqueror/i                      end
    def ie?()               @agent.to_s =~ /msie|trident/i && !opera?        end
    def gecko?()            @agent.to_s =~ /gecko/i && !webkit?              end
    def webkit?()           @agent.to_s =~ /webkit/i                         end
    def superfeedr?()       @agent.to_s =~ /superfeedr/i                     end
    def google?()           @agent.to_s =~ /googlebot/i                      end
    def yahoo?()            @agent.to_s =~ /yahoo/i                          end
    def yandex?()           @agent.to_s =~ /yandex/i                         end
    def baidu?()            @agent.to_s =~ /baidu/i                          end
    def duckduckgo?()       @agent.to_s =~ /duckduckbot/i                    end
    def bing?()             @agent.to_s =~ /bingbot/i                        end
    def applebot?()         @agent.to_s =~ /applebot/i                       end
    def semrush?()          @agent.to_s =~ /semrushbot/i                     end
    def ahrefs?()           @agent.to_s =~ /ahrefsbot/i                      end
    def mj12?()             @agent.to_s =~ /mj12bot/i                        end
    def dotbot?()           @agent.to_s =~ /dotbot/i                         end
    def blexbot?()          @agent.to_s =~ /blexbot/i                        end
    def uptimerobot?()      @agent.to_s =~ /uptimerobot/i                    end
    def facebot?()          @agent.to_s =~ /facebot/i                        end
    def ia_archiver?()      @agent.to_s =~ /ia_archiver/i                    end
    def searchengine?
      @agent.to_s =~ /\b(Baidu|Gigabot|Googlebot|libwww-perl|lwp-trivial|msnbot|SiteUptime|Slurp|WordPress|ZIBB|ZyBorg|Yahoo|bing|superfeedr|DuckDuckBot|YandexBot|Sogou|Exabot|facebot|ia_archiver|Applebot|SemrushBot|AhrefsBot|MJ12bot|DotBot|BLEXBot|UptimeRobot)\b/i
    end

  end
end
