require 'zlib'
require 'digest/sha1'
require_relative 'commit'
require_relative 'tree'
require_relative 'blob'

module TrueGrit
  class ObjectStore
    def self.retrieve(base, hash, parent)
      f = absolute_path(base, hash)
      data = Zlib::Inflate.inflate(File.binread(f))
      raise 'Checksum error!' unless Digest::SHA1.hexdigest(data).downcase == hash
      create_object(data, parent)
    end

    def self.contains?(base, hash)
      File.exists?(absolute_path(base, hash))
    end

    def self.absolute_path(base, hash)
      File.join(base, 'objects', hash[0..1], hash[2..-1])
    end

    def self.get_data(object)
      raise 'Unsupported object for storage: ' + object.class.name unless [Blob, Commit, Tree].include?(object.class)

      type = /::(\w+)$/.match(object.class.name.downcase)[1]

      data = object.data
      header = "#{type} #{data.length}\0"
      payload = header + data
      sha = Digest::SHA1.hexdigest(payload).downcase
      return sha,payload
    end

    def self.raw(object)
      sha, payload = get_data(object)
      comp = Zlib::Deflate.deflate(payload)
      return sha,comp
    end

    def self.store(base, object)
      sha,comp = raw(object)

      dir = File.join(base, 'objects', sha[0..1])
      Dir.mkdir(dir) unless Dir.exists?(dir)

      path = File.join(dir, sha[2..-1])
      return sha if File.exists?(path)
      file = File.open(path, 'wb')
      file.write(comp)
      file.flush
      file.close
      sha
    end

    def self.map(rep)
      map = {}
      base = repo.path
      Dir.foreach(File.join(base, 'objects')) do |pa|
        next unless pa.length == 2
        Dir.foreach(File.join(base, 'objects', pa)) do |pb|
          hash = "#{pa}#{pb}"
          map[hash] = repo.get_object(hash)
        end
      end
      map
    end

    private
    def self.create_object(data, parent)
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
  end
end