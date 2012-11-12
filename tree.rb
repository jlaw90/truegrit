require 'stringio'
require_relative 'store'
require_relative 'util'

module TrueGrit
  class Tree < Array
    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    def checkout(path)
      Util.mkdir(path)
      self.each { |e|
        p = File.join(path, e.name)
        if e.mode == '120000'
          begin
            File.symlink(e.content.data, p)
            next
          rescue e
            puts e
            # Just skip the next statement
            puts 'Checking out a symlink on windows, creating as a textfile...'
          end
        elsif e.mode == '160000'
          puts 'Gitlinks not yet supported! (submodules)'
          next
        end
        data = e.content
        if data.is_a?(Tree)
          data.checkout(p)
        elsif data.is_a?(Blob)
          f = File.new(p, 'wb')
          f.write(data.data)
          f.flush
          f.close
        else
          raise "Unknown entry in tree: #{data}"
        end
      }
    end

    def self.read(data, repo)
      stream = StringIO.new(data)
      tree = Tree.new(repo)
      until stream.eof?
        mode = stream.gets(' ').chop
        name = stream.gets(?\0).chop
        sha = ShaHash.new(stream.read(20))
        tree << TreeEntry.new(tree, mode, name, sha)
      end
      tree
    end

    def data
      sort! {|e1,e2| e1.name <=> e2.name }
      str = ''
      self.each do |e|
        str += "#{e.mode} #{e.name}\0"
        str += e.sha.sha
      end
      str
    end

    def map(path=nil)
      res = {}
      path = '' if path.nil?
      self.each do |e|
        fpath = File.join(path, e.name)[1..-1]
        res[fpath] = TreeMap.from_entry(e) unless e.mode == '40000'
        res[fpath] = e.content.map(path) if e.mode == '40000'
      end
      res
    end
  end

  class TreeMap
    attr_reader :name, :file

    def initialize(name, file)
      @name = name
      @file = file
    end

    def self.from_entry(e)
      TreeMap.new(e.name, e.content)
    end
  end

  class TreeEntry
    attr_reader :mode, :name, :sha

    def initialize(tree, mode, name, sha)
      @tree = tree
      @mode = mode
      @name = name
      @sha = sha
    end

    def content
      @tree.repo.retrieve_object(@sha)
    end

    def to_s
      "#{mode} #{@name}"
    end
  end
end