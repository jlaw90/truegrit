require 'time'

module TrueGrit
  class Author
    attr_reader :name, :email

    def initialize(name, email)
      @name = name
      @email = email
    end

    def data
      "#@name <#@email>"
    end

    def self.read(data)
      parts = data.split(' ')
      email = parts[-1][1..-2]
      name = parts[0..-2].join ' '
      return Author.new(name, email)
    end

    def to_s
      "#@name <#@email>"
    end
  end
end