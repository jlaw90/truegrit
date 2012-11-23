require 'fileutils'

require_relative 'store'
require_relative 'stage'
require_relative 'config'
require_relative 'util'
require_relative 'commit'

module TrueGrit
  class Repo
    attr_reader :path, :working_path, :store, :stage, :config

    def initialize(path)
      if Dir.exists?(File.join(path, '.git'))
        @working_path = File.absolute_path(path)
        @path = File.join(@working_path, '.git')
      else
        @path = path
      end
      @store = Store.new(self)
      @stage = Stage.new(self)
      @config = Config.new(self)
    end

    def retrieve_object(sha)
      @store.retrieve(sha, self)
    end

    def store_object(object)
      @store.store(object)
    end

    def has_object?(sha)
      @store.include?(sha)
    end

    def head
      head_path = File.join(@path, 'HEAD')
      return nil unless File.exists?(head_path)
      link = File.binread(head_path).chomp[5..-1]
      get_ref(link)
    end

    def get_ref(path)
      return nil if path.nil?
      raise "Invalid ref: #{path}" unless path[0..4] == 'refs/'
      abs_path = File.join(@path, path)
      if File.exists?(abs_path)
        hash_str = File.binread(abs_path).chomp
      else
        # Lookup in packed-refs
        pref_path = File.join(@path, 'packed-refs')
        if File.exists?(pref_path)
          f = File.open(pref_path, 'rb')
          begin
            f.each do |line|
              next if line.length == 0 or line[0] == '#' or line[0] == '^'
              match = line.match /^([0-9a-fA-F]{40}) (.+)$/
              next unless match[2].downcase == path.downcase
              hash_str = match[1]
              break
            end
          ensure
            f.close
          end
        end
      end
      return nil if hash_str.nil?
      retrieve_object(ShaHash.from_s(hash_str))
    end

    def get_branches
      branches = {}
      dir = File.join(@path, 'refs', 'heads')
      Dir.foreach(dir) do |f|
        next if f == '.' or f == '..'
        branches[f] = ShaHash.from_s(File.binread(File.join(dir, f)).chomp)
      end
      # Packed refs
      pref_path = File.join(@path, 'packed-refs')
      return branches unless File.exists?(pref_path)
      f = File.open(pref_path, 'rb')
      pos = nil
      begin
        f.each do |line|
          next if line.length == 0 or line[0] == '#' or line[0] == '^'
          match = line.match /^([0-9a-fA-F]{40}) (.+)$/
          path = match[2].downcase
          next unless path[0..10] == 'refs/heads/'
          branches[path[11..-1]] = ShaHash.from_s(match[1])
        end
      ensure
        f.close
      end
      branches
    end

    def get_tags
      tags = {}
      dir = File.join(@path, 'refs', 'tags')
      Dir.foreach(dir) do |f|
        next if f == '.' or f == '..'
        tags[f] = ShaHash.from_s(File.binread(File.join(dir, f)).chomp)
      end
      # Packed refs
      pref_path = File.join(@path, 'packed-refs')
      return branches unless File.exists?(pref_path)
      f = File.open(pref_path, 'rb')
      pos = nil
      begin
        f.each do |line|
          next if line.length == 0 or line[0] == '#' or line[0] == '^'
          match = line.match /^([0-9a-fA-F]{40}) (.+)$/
          path = match[2].downcase
          next unless path[0..9] == 'refs/tags/'
          tags[path[10..-1]] = ShaHash.from_s(match[1])
        end
      ensure
        f.close
      end
      tags
    end

    def set_ref(commit, path)
      File.binwrite(commit.is_a?(Commit) ? store_object(commit) : commit.to_s, "#{File.join(@path, path)}\n")
    end

    def clone(path, bare=false)
      clone_path = bare ? path : File.join(path, '.git')
      Util.mkdir(clone_path)
      FileUtils.cp_r("#@path/.", clone_path)

      checkout(path) unless bare
      nil
    end

    def checkout(path)
      head.checkout(path)
    end


    # Make us more like Grit (to ease transition)
    def commits(commit=head)
      commits_for(commit)
    end

    def commit(author, message, committer = author)
      stage.commit(author, message, committer)
    end

    def add(file)
      stage.add(file)
    end

    def remove(file)
      stage.remove(file)
    end

    def self.init(path, bare=false)
      working_path = bare ? nil : File.absolute_path(path)
      path = File.join(path, '.git') unless bare
      path = File.absolute_path(path) # Paranoia
      Util.mkdir(path)
      f = File.open(File.join(path, 'HEAD'), 'wb')
      f.write("ref: refs/heads/master\n")
      f.close

      f = File.open(File.join(path, 'description'), 'wb')
      f.write('No description')
      f.close

      Util.mkdir(File.join(path, 'info'))

      f = File.open(File.join(path, 'info', 'exclude'), 'wb')
      f.close

      Util.mkdir(File.join(path, 'objects'))
      Util.mkdir(File.join(path, 'objects', 'info'))
      Util.mkdir(File.join(path, 'objects', 'pack'))

      Util.mkdir(File.join(path, 'refs'))
      Util.mkdir(File.join(path, 'refs', 'heads'))
      Util.mkdir(File.join(path, 'refs', 'tags'))

      repo = Repo.new(path, working_path)
                                      # Todo: more standard config options
      repo.config['core.bare'] = bare
      repo
    end

    private
    def commits_for(commit)
      res = []
      return res if commit.nil?
      res << commit
      commit.parents.each { |p| res += commits_for p }
      res
    end
  end
end