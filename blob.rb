require_relative 'util'

module TrueGrit
  class Blob
    attr_reader :data

    def initialize(content)
      @data = Util.crlf(content)
    end

    def self.from_file(path)
      Blob.new(File.binread(path))
    end
  end
end