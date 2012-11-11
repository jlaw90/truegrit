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

    def self.big_endian?
      [1,2].pack('S') == [1,2].pack('n')
    end

    def self.time_pack(time)
      secs = time.to_i
      i1 = secs & 0xffffffff
      i2 = (secs >> 32) & 0xffffffff
      # Todo: account for endianness
      [i1,i2].pack('NN')
    end

    def self.time_unpack(packed)
      i1,i2 = packed.unpack('NN')
      # Note: will overflow in 2018 or something like that, but git just compares the lower 32-bits
      # So so should we
      #secs = i1 | (i2 << 32) # Todo: account for endianness
      Time.at(i1)
    end

    def self.time_parse(secs, tz)
      Time.at(secs.to_i) + (60 * 60 * tz.to_i)
    end

    def self.time_format(time)
      time.strftime("%s %z")
    end

    def self.crc32(data)
      Zlib.crc32(data)
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
            stats.unprintable += 1
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