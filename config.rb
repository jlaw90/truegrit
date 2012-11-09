module TrueGrit
  class Config < Hash
    def initialize(repo)
      @repo = repo

      read
    end

    alias :'super_set' :'[]='

    def []=(key, value)
      sup = super
      super_set(key, value)
      save
    end

    private
    def read
      loc = File.join(@repo.path, 'config')
      return unless File.exists?(loc)
      data = File.binread(loc)
      data.gsub!(/(#|;).*$/, '')
      section = nil
      data.lines.each { |line|
        line.strip!
        next if line.length == 0

        if line[0] == '[' and line[-1] == ']'
          section = line[1..-2]
          next
        end

        if (match = /(\w+) = (.*)/.match(line))
          key = match[1]
          value = match[2]
          realkey = section.nil? ? key : "#{section}.#{key}"

          if has_key?(realkey)
            old = self[realkey]
            if old.kind_of?(Array)
              old << value
              super_set(realkey, old)
            else
              super_set(realkey, [old, value])
            end
          else
            super_set(realkey, value)
          end
        end
      }
    end

    def save
      loc = File.join(@repo.path, 'config')
      f = File.open(loc, 'wb')
      keys = self.keys.sort!
      csec = nil
      keys.each { |key|
        section, lkey = key.split('.', 2)
        unless csec == section
          f.write "[#{section}]\n"
          csec = section
        end
        f.write "  #{lkey} = #{self[key]}"
      }
      f.flush
      f.close
    end
  end
end