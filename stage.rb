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
      se = StageEntry.from_file(@repo, file)
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
    ## Basically calls add on every file that's being tracked (that exists)
    ## This won't remove deleted paths (should it?)
    def restage
      raise 'Cannot restage on a bare repository' if @repo.working_path.nil?
      each do |p|
        exists = File.exists?(File.join(@repo.working_path, p.name))
        add(p.name) if exists
      end
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
        branches[branch_name] << TreeEntry.new(branch,
                                               e.stat.symlink? ? '120000' : e.stat.executable? ? '100755' : '100644',
                                               File.basename(e.name),
                                               e.sha)
      end

      # Consolidate branches...
      branches.sort { |b1, b2| b1[0].length <=> b2[0].length }.reverse.each do |dir, branch|
        next if dir == '' # Skip root
        parent_branch = File.dirname(dir)
        parent_branch = '' if parent_branch == '.'
        parent = branches[parent_branch]
        parent << TreeEntry.new(parent, '40000', File.basename(dir), @repo.store_object(branch))
      end

      parent = @repo.head.sha
      treehash = @repo.store_object(tree)

      @repo.set_head(Commit.new(@repo, treehash, parent, author, committer, Time.now, Time.now, message))
    end

    # todo: reset command (copy from commit to tmp, stat and change staged entry to that [git reset HEAD file])

    def status
      raise 'Cannot check status in a bare repository...' if @repo.working_path.nil?

      wmap = working_map
      hmap = head_map
      smap = {}
      self.each { |se| smap[se.name] = se }

      # Todo: steals gits way of doing this...
      results = {}
      results[:untracked] = [] # Not being tracked
      results[:unmodified] = [] # working == HEAD
      results[:modified] = [] # stage != working
      results[:staged] = [] # stage != HEAD
      results[:new] = [] # head doesn't contain it
      results[:deleted] = [] # head contained it, working doesn't

      wmap.keys.each do |w|
        se = wmap[w]
        if hmap.has_key?(w)
          results[:unmodified] << se if hmap[w] == se.sha
        end

        if smap.has_key?(w)
          results[:staged] << se if smap[w].sha != hmap[w] and !results[:unmodified].include?(se)
          results[:modified] << se if smap[w].modified?(se)
        else
          results[:untracked] << se
        end
      end

      # Get added and deleted keys
      smap.keys.each do |w|
        se = wmap[w]
        next unless results[:modified].include?(se)
        results[:new] << se unless hmap.has_key?(w)
      end

      hmap.keys.each do |w|
        results[:deleted] << StageEntry.new(w, hmap[w], nil, nil) unless wmap.has_key?(w)
      end
      results
    end

    private
    def read
      loc = File.join(@repo.path, 'index')
      return unless File.exists?(loc)
      f = File.open(loc, 'rb')
      size = File.size(loc)

      # Index header "DIRC" version count
      magic, ver=nil
      raise "Invalid index file #{magic} #{ver}" unless ((magic = f.read(4)) == 'DIRC' and
          (ver = f.read(4).unpack('N')[0]) == 2)
      count = f.read(4).unpack('N')[0]

      # Check checksum here now, why read if data is corrupted...
      # Compute checksum
      epos = size - 20
      f.pos = 0
      checksum_payload = f.read(epos)
      computed = Digest::SHA1.digest(checksum_payload)
      checksum_payload = nil
      raise 'Staging area checksum is invalid!' unless computed == f.read(20)
      f.pos = 12


      count.times do
        ctime = Util.time_unpack(f.read(8))
        mtime = Util.time_unpack(f.read(8))
        dev = f.read(4).unpack('N')[0]
        inode = f.read(4).unpack('N')[0]
        mode = f.read(4).unpack('N')[0]
        uid = f.read(4).unpack('N')[0]
        gid = f.read(4).unpack('N')[0]
        size = f.read(4).unpack('N')[0]
        sha = ShaHash.new(f.read(20))
        flags = f.read(2).unpack('n')[0]
        name_len = flags & 0xfff
        flags &= 0xf000 # Remove name length from flags...
        name = f.read(name_len)
        raise 'Expected null!' unless f.read(1) == ?\0

        # Padding to multiple of 8
        size = 55 + name_len
        pad = (8 - (size % 8)) % 8
        f.read(pad)
        unless @repo.includes_object?(sha)
          puts 'An item in the staging area appears to not exist in the object store, removing,,,'
          next
        end

        self << StageEntry.new(name, sha, StageStat.new(ctime, mtime, dev, inode, mode, uid, gid, size), flags)
      end

      # Todo: process & store!
      while f.pos < epos
        name = f.read(4)
        puts name
        size = f.read(4).unpack('N')[0]
        extd = f.read(size)
        raise 'Unhandled major extension in index: ' + name if name[0] >= ?A and name[0] <= ?Z
      end
    ensure
      f.close unless f.nil?
    end

    def save
      loc = File.join(@repo.path, 'index')
      file = File.open(loc, 'w+b')
      file.write("DIRC" + [2].pack('N'))
      file.write([count].pack('N'))

      sort! { |e, e1| e.name <=> e1.name }

      self.each do |e|
        file.write(Util.time_pack(e.stat.ctime))
        file.write(Util.time_pack(e.stat.mtime))
        file.write([e.stat.dev].pack('N'))
        file.write([e.stat.ino].pack('N'))
        file.write([e.stat.mode].pack('N'))
        file.write([e.stat.uid].pack('N'))
        file.write([e.stat.gid].pack('N'))
        file.write([e.stat.size].pack('N'))
        file.write(e.sha.sha)

        flags = e.flags & 0xf000
        flags |= e.name.length & 0xfff
        file.write([flags].pack('n'))
        file.write("#{e.name}\0")

        # Padding to multiple of 8
        size = 55 + e.name.length
        pad = (8 - (size % 8)) % 8
        file.write(?\0 * pad)
      end

      # TODO: store extensions!


      # Compute checksum
      checksum_end = file.pos
      file.pos = 0
      checksum_payload = file.read(checksum_end)
      computed = ShaHash.hash(checksum_payload)
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
      root.each do |e|
        full_path = File.join(path, e.name)
        obj = e.content
        map[full_path[1..-1]] = e.sha unless obj.is_a?(Tree)
        map.merge!(head_map(obj, full_path)) if obj.is_a?(Tree)
      end
      map
    end
  end

  class StageEntry
    attr_reader :stat, :sha, :flags, :name

    def initialize(name, sha, stat, flags)
      @stat = stat
      @sha = sha
      @flags = flags
      @name = name
    end

    def modified?(other)
      # Todo: Do we need hash comparison?
      (@stat.mtime.to_i & 0xffffffff) != (other.stat.mtime.to_i & 0xffffffff) or @sha != other.sha
    end

    def self.from_file(repo, path)
      path = File.absolute_path(path)
      sha = repo.store_object(Blob.from_file(path))
      relname = path[repo.working_path.length+1..-1]
      stat = File.lstat(path)
      StageEntry.new(relname, sha, stat, 0)
    end

    def to_s
      @name
    end
  end

  class StageStat
    attr_reader :ctime, :mtime, :dev, :ino, :mode, :uid, :gid, :size

    def initialize(ctime, mtime, dev, inode, mode, uid, gid, size)
      # Todo: store ctime and mtime as
      @ctime = ctime
      @mtime = mtime
      @dev = dev
      @ino = inode
      @mode = mode
      @uid = uid
      @gid = gid
      @size = size
    end

    def symlink?
      flag = @mode & 0x170000
      symlink = flag == 0120000
      return symlink
    end

    def executable?
      ((@mode & 1) == 1)
    end
  end
end