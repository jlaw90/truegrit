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

    def retrieve(hash, parent)
      f = absolute_path(hash)
      return Store::create_object(File.binread(f), parent) if File.exists?(f)
      @packs.each { |p| return p[hash].retrieve if p.include?(hash) }
      raise "#{hash} not found in file or pack files"
    end

    def include?(base, hash)
      return true if File.exists?(absolute_path(hash))
      @packs.each { |p| return true if p.include?(hash) }
      false
    end

    def absolute_path(hash)
      hash = hash.to_s
      File.join(@repo.path, 'objects', hash[0..1], hash[2..-1])
    end

    def self.hash(object,return_payload=false)
      raise 'Unsupported object for storage: ' + object.class.name unless [Blob, Commit, Tree].include?(object.class)

      type = /::(\w+)$/.match(object.class.name.downcase)[1]

      data = Util.crlf(object.data) # Fix-up newlines
      header = "#{type} #{data.length}\0"
      payload = header + data
      hash = ShaHash.calculate(payload)
      return return_payload ? [hash, payload]: hash
    end

    def store(object)
      sha, comp = Store::payload(object)
      path = absolute_path(sha)
      puts "#{sha} from #{object}"
      return sha if File.exists?(path) # Don't re-write, waste of time
      Util.mkdir(File.dirname(path))
      file = File.open(path, 'wb')
      file.write(comp)
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
          hash = ShaHash.from_s("#{pa}#{pb}")
          map[hash] = retrieve(hash)
        end
      end
      map
    end

    private
    def self.create_object(data, parent)
      data = Zlib::Inflate.inflate(data)
      header, data = data.split(?\0, 2)
      type, size = header.split(' ', 2)
      size = size.to_i
      raise 'Invalid header in object (unknown type)' unless %w(commit blob tree).include?(type)
      raise 'Invalid header in object (size mismatch)' if data.length != size
      case type
        when 'commit'
          return Commit.read(data, parent)
        when 'tree'
          return Tree.read(data, parent)
        when 'blob'
          return Blob.new(data)
        else
          raise 'Unhandled object type: ' + type
      end
    end

    def self.payload(object)
      sha, payload = hash(object,true)
      comp = Zlib::Deflate.deflate(payload)
      return sha, comp
    end
  end
end