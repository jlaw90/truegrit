require 'fileutils'

module TrueGrit
  class Util
    def self.crlf(data)
      # Git-based text determination...
      return data if is_binary(data)
      data.gsub(/(\r\n?)/, "\n")
    end

    def self.mkdir(path)
      FileUtils.mkpath(path) unless Dir.exists?(path)
    end

    def self.is_binary(data)
      stats = text_stats(data)
      stats.nul != 0 or (stats.printable >> 7) < stats.unprintable
    end

    private
    # Ripped almost entirely from git source (smart!)
    def self.text_stats(data)
      stats = TextStat.new
      prev = nil

      data.each_char do |c|
        case
          when c == ?\r then
            stats.cr += 1
          when c == ?\n then
            stats.lf += 1
            stats.crlf += 1 if prev == ?\r
          when c == ?\0 then
            stats.nul += 1
            stat.unprintable += 1
          when ([?\b, ?\t, ?\014, ?\033].include?(c) or (c >= ?\040 and c <= ?\177)) then
            stats.printable += 1
          else
            stats.unprintable += 1
        end
        prev = c
      end
      stats
    end

    class TextStat
      attr_accessor :nul, :cr, :lf, :crlf, :printable, :unprintable

      def initialize
        @nul, @cr, @lf, @crlf, @printable, @unprintable = 0, 0, 0, 0, 0, 0
      end
    end
  end
end