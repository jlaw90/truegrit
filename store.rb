require 'zlib'
require 'digest/sha1'
require_relative 'commit'
require_relative 'tree'
require_relative 'blob'
require_relative 'pack'

module TrueGrit
  class Store
    def initialize(repo)
      @repo = repo
      @cache = {}

      # Load pack files...
      @packs = []
      pack_path = File.join(@repo.path, 'objects', 'pack')
      return unless File.exists?(pack_path)
      Dir.foreach(pack_path) do |f|
        next unless File.extname(f) == '.idx'
        path = File.join(pack_path, f[0..-5])
        @packs << Pack.new(@repo, "#{path}.idx", "#{path}.pack")
      end
    end

    def retrieve(sha, parent)
      return Store::create_object(retrieve_raw(sha), parent, sha)
    end

    def retrieve_raw(sha)
      f = absolute_path(sha)
      return @cache[sha] if @cache.include?(sha)
      return (@cache[sha] = Zlib::Inflate.inflate(File.binread(f))) if File.exists?(f)
      @packs.each do |p|
        if p.include?(sha)
          @cache[sha] = p.unpack(sha)
          return retrieve_raw(sha) # Now it's unpacked we should have it!
        end
      end
      raise "#{sha} not found in file or pack files"
    end

    def include?(sha)
      return true if @cache.include?(sha) or File.exists?(absolute_path(sha))
      @packs.each { |p| return true if p.include?(sha) }
      false
    end

    def absolute_path(sha)
      s = sha.to_s
      File.join(@repo.path, 'objects', s[0..1], s[2..-1])
    end

    def self.hash(object,return_payload=false)
      raise 'Unsupported object for storage: ' + object.class.name unless [Blob, Commit, Tree].include?(object.class)

      type = /::(\w+)$/.match(object.class.name.downcase)[1]

      data = Util.crlf(object.data) # Fix-up newlines
      header = "#{type} #{data.length}\0"
      payload = header + data
      sha = ShaHash.calculate(payload)
      return return_payload ? [sha, payload]: sha
    end

    def store(object)
      sha,data = Store::hash(object, true)
      store_raw(sha, data)
    end

    def store_raw(sha, data)
      path = absolute_path(sha)
      return sha if File.exists?(path) # Don't re-write, waste of time
      Util.mkdir(File.dirname(path))
      file = File.open(path, 'wb')
      file.write(Zlib::Deflate.deflate(data))
      file.flush
      file.close
      File.chmod(0644, path)# Make read-only (git does this)
      sha
    end

    def map
      map = {}
      Dir.foreach(File.join(@repo.working_path, 'objects')) do |pa|
        next unless pa.length == 2
        Dir.foreach(File.join(@repo.working_path, 'objects', pa)) do |pb|
          sha = ShaHash.from_s("#{pa}#{pb}")
          map[sha] = retrieve(sha)
        end
      end
      map
    end

    private
    def self.create_object(src, parent,sha=nil)
      header, data = src.split(?\0, 2)
      type, size = header.split(' ', 2)
      size = size.to_i
      raise 'Invalid header in object (unknown type)' unless %w(commit blob tree).include?(type)
      raise 'Invalid header in object (size mismatch)' if data.length != size
      case type
        when 'commit'
          return Commit.read(data, parent, sha)
        when 'tree'
          return Tree.read(data, parent)
        when 'blob'
          return Blob.new(data)
        else
          raise 'Unhandled object type: ' + type
      end
    end
  end
end