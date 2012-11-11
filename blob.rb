require_relative 'util'

module TrueGrit
  class Blob
    attr_reader :data

    def initialize(content,source=nil)
      @data = Util.crlf(content)
      @source = source
    end

    def self.from_file(path)
      return Blob.new(File.readlink(path), path) if File.symlink?(path)
      Blob.new(File.binread(path), path)
    end

    alias :lame_to_s :to_s

    def to_s
      return lame_to_s if @source.nil?
      "#{@source}"
    end
  end
end