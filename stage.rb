require 'stringio'
require_relative 'blob'
require_relative 'tree'
require_relative 'commit'

module TrueGrit
  class Stage < Array
    def initialize(repo)
      @repo = repo

      read
    end

    # Works the same as git add
    # Adds a file to the staging area if not present
    # If present, updates attributes
    def add(file)
      raise 'Cannot add files to a bare repository...' if @repo.working_path.nil?
      p = File.join(@repo.working_path, file)
      raise 'Cannot add non-existant file' unless File.exists?(p)
      hash = @repo.put_object(Blob.new(File.binread(p)))
      stat = File.stat(p)
      se = StageEntry.new(file, hash,
                          StageStat.new(stat.ctime, stat.mtime, stat.dev, stat.ino, stat.mode, stat.uid, stat.gid, stat.size),
                          0)
      staged = self.select { |e| e.name == file }.first
      self[self.index(staged)] = se unless staged.nil?
      self << se if staged.nil?

      save
    end

    ## This command removes a file from the staging area
    ## It will no longer be tracked in the file system
    def remove(file)
      raise 'Cannot remove files from a bare repository...' if @repo.working_path.nil?
      self.delete_if { |e| e.name == file }
      save
    end

    ## Restages all the files in the working directory
    ## Basically calls add on every file that's being tracked
    def restage
      raise 'Cannot restage on a bare repository' if @repo.working_path.nil?
      each { |p| add(p.name) }
    end

    ## Commit all staged files
    def commit(author, message, committer = author)
      raise 'Cannot commit in a bare repository!' if @repo.working_path.nil?

      branches = {}
      tree = branches[''] = Tree.new(@repo)

      self.each do |e|
        # Make sure the branches exist...
        parts = e.name.split('/')
        mkpth = ''
        (parts.length-1).times do |i|
          mkpth = File.join(mkpth, parts[i])
          mkpth = mkpth[1..-1] if mkpth[0] == '/'
          branches[mkpth] = Tree.new(@repo) unless branches.has_key?(mkpth)
        end unless parts.length == 0

        branch_name = File.dirname(e.name)
        branch_name = branch_name == '.' ? '' : branch_name
        branch = branches[branch_name]
        path = File.join(@repo.working_path, e.name)
        branches[branch_name] << TreeEntry.new(branch,
                                               File.symlink?(path) ? '120000' : File.executable?(path) ? '100755' : '100644',
                                               File.basename(e.name),
                                               @repo.put_object(Blob.from_file(path)))
      end

      # Consolidate branches...
      branches.sort { |b1, b2| b1[0].length <=> b2[0].length }.reverse.each do |dir, branch|
        next if dir == '' # Skip root
        parent_branch = File.dirname(dir)
        parent_branch = '' if parent_branch == '.'
        parent = branches[parent_branch]
        parent << TreeEntry.new(parent, '40000', File.basename(dir), @repo.put_object(branch))
      end

      treehash = @repo.put_object(tree)
      parent = @repo.head_hash

      @repo.set_head(Commit.new(@repo, treehash, parent, author, committer, Time.now, Time.now, message))
    end

    # todo: reset command (copy from commit to tmp, stat and change staged entry to that [git reset HEAD file])

    def status
      raise 'Cannot check status in a bare repository...' if @repo.working_path.nil?

      wmap = working_map
      hmap = head_map
      smap = {}
      self.each { |se| smap[se.name] = se }

      results = {}
      results[:untracked] = [] # Not being tracked
      results[:unmodified] = [] # working == HEAD
      results[:modified] = [] # stage != working
      results[:staged] = [] # stage != HEAD

      wmap.keys.each do |w|
        se = wmap[w]
        if hmap.has_key?(w)
          results[:unmodified] << se unless hmap[w] != se.hash
        end

        if smap.has_key?(w)
          results[:staged] << se unless results[:unmodified].include?(se) or smap[w].hash == hmap[w]
          results[:modified] << se if smap[w].modified?(se)
        else
          results[:untracked] << se
        end

      end

      results
    end

    private
    def read
      loc = File.join(@repo.path, 'index')
      return unless File.exists?(loc)
      data = File.binread(loc)
      stream = StringIO.new(data)

      # Index header "DIRC" version count
      magic, ver=nil
      raise "Invalid index file #{magic} #{ver}" unless ((magic = stream.read(4)) == 'DIRC' and (ver = stream.read(4).unpack('N')[0]) == 2)
      count = stream.read(4).unpack('N')[0]

      count.times do
        ctime = Time.at(stream.read(4).unpack('N')[0] | (stream.read(4).unpack('N')[0] << 32))
        mtime = Time.at(stream.read(4).unpack('N')[0] | (stream.read(4).unpack('N')[0] << 32))
        dev = stream.read(4).unpack('N')[0]
        inode = stream.read(4).unpack('N')[0]
        mode = stream.read(4).unpack('N')[0]
        uid = stream.read(4).unpack('N')[0]
        gid = stream.read(4).unpack('N')[0]
        size = stream.read(4).unpack('N')[0]
        hash = stream.read(20).chars.to_a.map { |c| sprintf("%02x", c.ord) }.join
        flags = stream.read(2).unpack('n')[0]
        name_len = flags & 0xfff
        flags &= 0xf000 # Remove name length from flags...
        name = stream.read(name_len)
        raise 'Expected null!' unless stream.read(1) == ?\0

        # Padding to multiple of 8
        size = 55 + name_len
        pad = (8 - (size % 8)) % 8
        stream.read(pad)
        raise 'Uh-oh' unless @repo.contains_object?(hash)

        self << StageEntry.new(name, hash, StageStat.new(ctime, mtime, dev, inode, mode, uid, gid, size), flags)
      end

      # Todo: process & store!
      while data.length - stream.pos != 20
        name = stream.read(4)
        puts name
        size = stream.read(4).unpack('N')[0]
        extd = stream.read(size)
        raise 'Unhandled major extension in index: ' + name if name[0] >= ?A and name[0] <= ?Z
      end

      # Compute checksum
      checksum_end = stream.pos
      stream.pos = 0
      checksum_payload = stream.read(checksum_end)
      computed = Digest::SHA1.digest(checksum_payload)
      checksum_payload = nil
      read = stream.read(20)
      raise 'Index file checksum is invalid!' unless computed == read
    end

    def save
      # Todo: THERE IS A VERY IMPORTANT BUG HERE!!!
      # Todo: I JUST HAVEN'T FOUND IT YET!
      loc = File.join(@repo.path, 'index')
      file = File.open(loc, 'w+b')
      file.write("DIRC" + [2].pack('N'))
      file.write([count].pack('N'))

      sorted = self.sort { |e, e1| e.name <=> e1.name }

      sorted.each do |e|
        file.write([e.stat.ctime.to_i & 0xffffffff, e.stat.ctime.to_i & 0xffffffff00000000].pack('NN'))
        file.write([e.stat.mtime.to_i & 0xffffffff, e.stat.mtime.to_i & 0xffffffff00000000].pack('NN'))
        file.write([e.stat.dev].pack('N'))
        file.write([e.stat.inode].pack('N'))
        file.write([e.stat.mode].pack('N'))
        file.write([e.stat.uid].pack('N'))
        file.write([e.stat.gid].pack('N'))
        file.write([e.stat.size].pack('N'))
        rawsha = [e.hash].pack('H*')
        raise 'Uh-oh' unless rawsha.length == 20
        file.write(rawsha)

        flags = e.flags & 0xf000
        flags |= e.name.length & 0xfff
        file.write([flags].pack('n'))
        file.write("#{e.name}\0")

        # Padding to multiple of 8
        size = 55 + e.name.length
        pad = (8 - (size % 8)) % 8
        file.write(?\0 * pad)
      end

      # Todo: store extensions!


      # Compute checksum
      checksum_end = file.pos
      file.pos = 0
      checksum_payload = file.read(checksum_end)
      computed = Digest::SHA1.digest(checksum_payload)
      file.write(computed)
      file.flush
      file.close
    end

    # Todo: not calculate hash every time
    def working_map(root = @repo.working_path)
      map = {}
      sublen = @repo.working_path.length + 1
      Dir.entries(root).each { |f|
        next if f == '.' or f == '..' or f[0..4] == '.git'
        # Todo: check config for ignore dot files setting, use .gitignore, etc.
        full_path = File.join(root, f)
        dir = File.directory?(full_path)
        map[full_path[sublen..-1]] = StageEntry.from_file(@repo, full_path) unless dir
        map.merge!(working_map(File.join(root, f))) if dir
      }
      map
    end

    def head_map(root = @repo.head_hash.nil? ? [] : @repo.head.tree, path = '')
      map = {}
      root.each { |e|
        full_path = File.join(path, e.name)
        obj = e.content
        map[full_path[1..-1]] = e.sha unless obj.is_a?(Tree)
        map.merge!(head_map(obj, full_path)) if obj.is_a?(Tree)
      }
      map
    end
  end

  class StageEntry
    attr_reader :stat, :hash, :flags, :name

    def initialize(name, hash, stat, flags)
      @stat = stat
      @hash = hash
      @flags = flags
      @name = name
    end

    def modified?(other)
      # Todo: hash comparison? Will waste a lot of time...
      @stat.modified?(other.stat) or @hash != other.hash
    end

    def self.from_file(repo, path)
      path = File.absolute_path(path)
      blob = Blob.from_file(path)
      # Todo: sha calculation is time consuming...
      sha, data = ObjectStore.get_data(blob)
      relname = path[repo.working_path.length+1..-1]
      stat = StageStat.from_file(path)
      StageEntry.new(relname, sha, stat, 0)
    end

    def to_s
      @name
    end
  end

  class StageStat
    attr_reader :ctime, :mtime, :dev, :inode, :mode, :uid, :gid, :size

    def initialize(ctime, mtime, dev, inode, mode, uid, gid, size)
      @ctime = ctime
      @mtime = mtime
      @dev = dev
      @inode = inode
      @mode = mode
      @uid = uid
      @gid = gid
      @size = size
    end

    def modified?(stat)
      @mtime != stat.mtime
    end

    def self.from_file(path)
      stat = File.stat(path)
      StageStat.new(stat.ctime, stat.mtime, stat.dev, stat.ino, stat.mode, stat.uid, stat.gid, stat.size)
    end
  end
end