require 'zlib'
require_relative 'sha_hash'
require_relative 'util'
require_relative 'tree'
require_relative 'commit'
require_relative 'blob'

module TrueGrit
  class Pack < Hash
    def initialize(repo, idx, data)
      @repo = repo
      @idx_path = idx
      @pack_path = data

      read
    end

    def retrieve(entry)
      f = File.open(@pack_path, 'rb')
      f.pos = entry.offset

      # Header
      # 1 byte, MSB == size extension
      # Type, 3-bits
      # size (lower 4 bits)
      b = f.readbyte
      type = PackType.from_i((b >> 4) & 0x07)
      size = (b & 0x0f)
      shift = 4
      # More size info
      while ((b >> 7) & 1) == 1
        b = f.readbyte
        size |= ((b & 0x7f) << shift)
        shift += 7
      end

      # Return object...
      data = f.read(size)
      f.close
      # Check crc
      #crc = Util.crc32(data)
      #puts entry.crc
      #puts crc
      #puts "#{sprintf("%8x", crc)}, expected #{sprintf("%8x", entry.crc)}}"
      #raise 'CRC invalid' unless crc == entry.crc
      data = Zlib::Inflate.inflate(data)
      case type
        when CommitType
          Commit.read(data, @repo)
        when TreeType
          Tree.read(data, @repo)
        when BlobType
          Blob.new(data)
      end
    end

    private
    def read
      # Verify pack file header
      f = File.open(@pack_path, 'rb')
      head = ver = nil
      raise "Invalid pack file h=#{head},v=#{ver}" unless (head=f.read(4)) == "PACK" and
          (ver=f.read(4).unpack('N')[0]) == 2
      pack_count = f.read(4).unpack('N')[0]

      # Test the checksum, make sure it's not corrupt
      epos = File.size(@pack_path) - 20
      f.pos = 0
      pack_checksum = ShaHash.hash(f.read(epos))
      raise 'Pack file checksum invalid' unless pack_checksum == f.read(20)
      f.close

      # Read the index table

      # Verify header

      f = File.open(@idx_path, 'rb')
      head = ver = 'unread'
      raise "Invalid pack index file h=#{head},v=#{ver}" unless (head=f.read(4)) == "\xFFtOc" and
          (ver=f.read(4).unpack('N')[0]) == 2

      # Checksum!
      epos = File.size(@idx_path) - 20
      f.pos = 0
      idx_checksum = ShaHash.hash(f.read(epos))
      raise 'Pack index file checksum invalid' unless idx_checksum == f.read(20)

      # Stored checksum of pack
      f.pos -= 40
      idx_pack_checksum = f.read(20)
      raise 'Pack index file checksum for pack file does not match the packfile checksum' unless idx_pack_checksum == pack_checksum

      # continue...
      f.pos = 8

      # Read fan-out table...
      fanout = []
      255.times do |i|
        fanout[i] = f.read(4).unpack('N')[0]
      end
      count = f.read(4).unpack('N')[0]

      raise 'Pack count does not match index count!' unless count == pack_count

      name_table = []
      count.times do |i|
        name_table[i] = ShaHash.new(f.read(20))
      end

      crc_table = []
      count.times do |i|
        crc_table[i] = f.read(4).unpack('N')[0]
      end

      offset_table = []
      count.times do |i|
        offset_table[i] = f.read(4).unpack('N')[0]
      end

      # Todo: ! There is another table for pack files larger than 2GiB
      # To handle larger than 32-bit offsets!

      rem = epos - f.pos - 20

      raise 'Unknown data at end of pack file (if pack file is larger than 2GiB: not yet implemented)' if rem != 0

      count.times do |i|
        off = offset_table[i]
        raise 'Larger than 2 GiB offsets not currently supported' if ((off >> 31) & 1) == 1
        self[name_table[i]] = PackEntry.new(self, off, crc_table[i])
      end
    ensure
      f.close unless f.nil?
    end
  end

  class PackEntry
    attr_reader :offset, :crc

    def initialize(pack, offset, crc)
      @pack = pack
      @offset = offset
      @crc = crc
    end

    # retrieve data
    def retrieve
      @pack.retrieve(self)
    end
  end

  class PackType
    attr_reader :type

    def initialize(type)
      @type = type
    end

    def to_s
      case @type
        when 1
          return "Commit"
        when 2
          return "Tree"
        when 3
          return "Blob"
        when 4
          return "Tag"
        when 6
          return "Delta Offset"
        when 7
          return "Delta Reference"
        else
          return "Invalid"
      end
    end

    def self.from_i(i)
      case i
        when 1
          return CommitType
        when 2
          return TreeType
        when 3
          return BlobType
        when 4
          return TagType
        when 6
          return DeltaOffsetType
        when 7
          return DeltaReferenceType
        else
          raise "Invalid object type #{i}"
      end
    end

    def self.from_obj(obj)
      return CommitType if obj.is_a?(Commit)
      return TreeType if obj.is_a?(Tree)
      return BlobType if obj.is_a?(Blob)
      raise "Unsupported object #{obj}"
    end
  end

  CommitType = PackType.new(1)
  TreeType = PackType.new(2)
  BlobType = PackType.new(3)
  TagType = PackType.new(4)
  DeltaOffsetType = PackType.new(6)
  DeltaReferenceType = PackType.new(7)
end