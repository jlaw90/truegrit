require 'zlib'
require 'stringio'
require 'benchmark'
require_relative 'sha_hash'
require_relative 'util'
require_relative 'tree'
require_relative 'commit'
require_relative 'blob'

module TrueGrit
  class Pack
    def initialize(repo, idx, data)
      @repo = repo
      @idx = File.open(idx, 'rb')
      @pack = File.open(data, 'rb')
      @cache = {}

      read
    end

    def include?(sha)
      locate(sha)
      @cache.include?(sha) && @cache[sha] != false
    end

    def unpack(sha)
      # Locate file in index...
      raise 'We dont have this file, chief' unless include?(sha)

      entry = @cache[sha]
      off,crc = entry[:off], entry[:crc]
      @pack.pos = off

      # Header
      # 1 byte, MSB == size extension
      # Type, 3-bits
      # size (lower 4 bits)
      b = @pack.readbyte
      type = PackType.from_i((b >> 4) & 0x07)
      size = (b & 0x0f)
      shift = 4
      # More size info
      while (b & 0x80) != 0
        b = @pack.readbyte
        size += ((b & 0x7f) << shift)
        shift += 7
      end

      # Read any extraneous data (DELTAs mainly use this)
      case type
        when DeltaOffsetType
          b = @pack.readbyte
          offs = b & 0x7f
          while b & 0x80 != 0
            offs += 1
            b = @pack.readbyte
            offs = (offs << 7) + (b & 0x7f)
          end
          raise "Invalid offset #{offs}" if offs < 0 or offs >= off
          delta_off = off - offs
          idx = @table_offset[delta_off]
          @idx.pos = 8 + (256 * 4) + (idx * 20)
          delta_sha = ShaHash.new(@idx.read(20))
        when DeltaReferenceType
          delta_sha = ShaHash.new(@pack.read(20))
      end

      # Todo: check CRCs and shit

      # Decompress (why the fuck didn't they store the compressed size...)
      # Takes so much longer feeding a byte at a time....
      data = ''
      zstream = Zlib::Inflate.new
      begin
        data += zstream.inflate(@pack.readchar)
      end until data.length == size
      zstream.close

      # If this isn't a delta, prepend the header...
      data = "#{type.to_s} #{data.size}\0#{data}" unless type == DeltaReferenceType or type == DeltaOffsetType

      # Deserialise...
      # Todo: This won't work for read-only directories, hrm....
      return (type == DeltaReferenceType or type == DeltaOffsetType)?
          Pack::apply_delta(@repo.store.retrieve_raw(delta_sha), data):
          data
    end

    private
    def read
      # Todo: maybe enable checksum and header checks with an options?
      # While good in practise, checksumming the linux git packfile takes about 5 seconds...
      # Or am I just worrying too much about performance?
      # - James

      ## Verify pack file header
      #head = ver = nil
      #raise "Invalid pack file h=#{head},v=#{ver}" unless (head=@pack.read(4)) == "PACK" and
      #    (ver=@pack.read(4).unpack('N')[0]) == 2
      #pack_count = @pack.read(4).unpack('N')[0]
      #
      ## Test the checksum, make sure it's not corrupt
      #epos = @pack.size - 20
      #@pack.pos = 0
      #pack_checksum = ShaHash.hash(@pack.read(epos))
      #raise 'Pack file checksum invalid' unless pack_checksum == @pack.read(20)
      #
      ## Read the index table
      #
      ## Verify header
      #
      #head = ver = 'unread'
      #raise "Invalid pack index file h=#{head},v=#{ver}" unless (head=@idx.read(4)) == "\xFFtOc" and
      #    (ver=@idx.read(4).unpack('N')[0]) == 2
      #
      ## Checksum!
      #epos = @idx.size - 20
      #@idx.pos = 0
      #idx_checksum = ShaHash.hash(@idx.read(epos))
      #raise 'Pack index file checksum invalid' unless idx_checksum == @idx.read(20)
      #
      ## Stored checksum of pack
      #@idx.pos -= 40
      #idx_pack_checksum = @idx.read(20)
      #raise 'Pack index file checksum for pack file does not match the packfile checksum' unless idx_pack_checksum == pack_checksum

      # continue...
      @idx.pos = 8

      # Read fan-out table...
      @fanout = Array.new(256, 0) # Initialise arrays with size, should prevent reallocation
      256.times do |i|
        @fanout[i] = @idx.read(4).unpack('N')[0]
      end

      count = @fanout[255]

      #raise 'Pack count does not match index count!' unless count == pack_count

      # Read the offsets... (if we didn't do this, this library would be fast)
      # Todo: think up workarounds... lol
      @table_offset = {}

      # Not as fast as not reading anything and using random file access to search
      # But the fastest we can get while still keeping delta rebuilding fast
      # Unless anyone can think of another way?
      @idx.pos += (20 * count) + (4 * count)

      count.times do |i|
        @table_offset[@idx.read(4).unpack('N')[0]] = i
      end
    end

    # Locate an object by its hash
    # Should be pretty quick :)
    def locate(sha)
      return if @cache.include?(sha)

      sha_start = 8 + (256 * 4)
      crc_start = sha_start + (20 * @fanout[255])
      offset_start = crc_start + (4 * @fanout[255])
      b1 = sha.sha[0].ord
      ns = b1 == 0 ? 0 : @fanout[b1 - 1]
      ne = @fanout[b1]

      # sha table, crc table, offset table

      lo=ns
      hi=ne

      while lo < hi
        mid = (lo + hi)/2
        @idx.pos = sha_start + (mid * 20)
        psha = @idx.read(20)
        if psha < sha.sha
          lo = mid + 1
        elsif psha > sha.sha
          hi = mid
        else
          @idx.pos = crc_start + (mid * 4)
          crc = @idx.read(4).unpack('N')[0]
          @idx.pos = offset_start + (mid * 4)
          off = @idx.read(4).unpack('N')[0]
          @cache[sha] = {:off => off, :crc => crc}
          return
        end
      end
      @cache[sha] = false # Signify we don't have it!
    end

    def self.apply_delta(src, delta)
      base_type = src[0..src.index(' ')]
      src = src[src.index(?\0)+1..-1] # Strip the object header...

      deltastream = StringIO.new(delta)

      # Get the size (the size of the source data...)
      size = shift = i = 0
      begin
        b = deltastream.readbyte;
        size |= ((b & 0x7f) << i)
        i += 7;
      end while ((b & 0x80) != 0);

      raise 'Source data has wrong length!' unless size == src.length

      # Get the size of the resulting data
      size = shift = i = 0
      begin
        b = deltastream.readbyte;
        size |= ((b & 0x7f) << i)
        i += 7;
      end while ((b & 0x80) != 0);
      wanted_size = size

      out = ''
      while deltastream.pos < delta.length
        cmd = deltastream.readbyte

        if (cmd & 0x80) != 0
          cp_off = cp_size = 0
          cp_off = deltastream.readbyte if (cmd & 0x01) != 0
          cp_off |= (deltastream.readbyte << 8) if (cmd & 0x02) != 0
          cp_off |= (deltastream.readbyte << 16) if (cmd & 0x04) != 0
          cp_off |= (deltastream.readbyte << 24) if (cmd & 0x08) != 0
          cp_size = deltastream.readbyte if (cmd & 0x10) != 0
          cp_size |= (deltastream.readbyte << 8) if (cmd & 0x20) != 0
          cp_size |= (deltastream.readbyte << 16) if (cmd & 0x40) != 0
          cp_size = 0x10000 if cp_size == 0

          break if (cp_off + cp_size < cp_size || cp_off + cp_size > src.length || cp_size > size)

          cp_size.times do
            out += src[cp_off]
            cp_off += 1
          end
        elsif cmd != 0
          break if cmd > size
          cmd.times { out += deltastream.readchar }
        else
          # currently reserved, we'll throw a wobbly just like git does
          raise 'Unexpected delta opcode 0'
        end
      end

      # Sanity checks
      raise "Delta reflow problem built=#{out.length},rem=#{size},want=#{wanted_size}" unless out.length == wanted_size || size != 0

      "#{base_type} #{out.length}\0#{out}"
    end
  end

  class PackType
    attr_reader :type

    def initialize(type)
      @type = type
    end

    def to_s
      return case @type
               when 1 then
                 "commit"
               when 2 then
                 "tree"
               when 3 then
                 "blob"
               when 4 then
                 "tag"
               when 6 then
                 "delta offset"
               when 7 then
                 "delta reference"
             end
    end

    def self.from_i(i)
      return case i
               when 1 then
                 CommitType
               when 2 then
                 TreeType
               when 3 then
                 BlobType
               when 4 then
                 TagType
               when 6 then
                 DeltaOffsetType
               when 7 then
                 DeltaReferenceType
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