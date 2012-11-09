require 'stringio'
require_relative 'object_store'
require_relative 'util'

module TrueGrit
  class Tree < Array
    attr_reader :repo

    def initialize(repo)
      @repo = repo
    end

    def checkout(path)
      Util.mkdir(path)
      self.each {|e|
        data = e.content
        p = File.join(path, e.name)
        if data.is_a?(Tree)
          data.checkout(p)
        elsif data.is_a?(Blob)
          f = File.new(p, 'wb')
          f.write(data.data)
          f.flush
          f.close
        else
          raise 'Unknown entry in tree: ' + data.class
        end
      }
    end

    def self.read(data, repo)
      stream = StringIO.new(data)
      tree = Tree.new(repo)
      until stream.eof?
        mode = stream.gets(' ').chop
        name = stream.gets(?\0).chop
        sha = stream.read(20).chars.to_a.map { |c| sprintf("%02x", c.ord) }.join
        tree << TreeEntry.new(tree, mode, name, sha)
      end
      tree
    end

    def data
      str = ''
      self.each do |e|
        str += "#{e.mode} #{e.name}\0"
        str += [e.sha].pack('H*')
      end
      str
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
      ObjectStore.retrieve(@tree.repo.path, @sha, @tree.repo)
    end

    def to_s
      @name
    end
  end
end