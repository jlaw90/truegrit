require 'fileutils'

require_relative 'object_store'
require_relative 'stage'
require_relative 'config'
require_relative 'util'
require_relative 'commit'

module TrueGrit
  class Repo
    attr_reader :path, :working_path, :config, :stage

    def initialize(repo_path, working_path=nil)
      @path = File.absolute_path(repo_path)
      @working_path = File.absolute_path(working_path)
      @stage = Stage.new(self)
      @config = Config.new(self)
    end

    def get_object(hash)
      return nil if hash.nil?
      ObjectStore.retrieve(@path, hash, self)
    end

    def put_object(object)
      ObjectStore.store(@path, object)
    end

    def contains_object?(hash)
      ObjectStore.contains?(@path, hash)
    end

    # Todo: name properly for refs, tags, etc.
    def head(path=nil)
      get_object(head_hash(path))
    end

    def head_hash(path=nil)
      path = File.join(@path, path.nil? ? 'HEAD' : "refs/heads/#{path}")
      return nil unless File.exists?(path)
      data = File.binread(path).chomp

      # Follow ref:
      if data[0..4] == 'ref: '
        refpath = File.join(@path, data[5..-1])
        return nil unless File.exists?(refpath)
        data = File.binread(refpath).chomp
      end
      data
    end

    def set_head(commit, path=nil)
      path = File.join(@path, path.nil? ? 'HEAD' : "refs/heads/#{path}")
      value = commit.is_a?(Commit) ? put_object(commit) : commit.to_s
      data = File.binread(path).chomp

      # Check ref
      path = File.join(@path, data[5..-1]) if data[0..4] == 'ref: '

      f = File.open(path, 'wb')
      f.write("#{value}\n")
      f.flush
      f.close
    end

    def clone(path, bare=false)
      clone_path = bare ? path : File.join(path, '.git')
      Util.mkdir(clone_path)
      FileUtils.cp_r("#@path/.", clone_path)

      unless bare
        checkout(path)
      end
      nil
    end

    def checkout(path)
      head.checkout(path)
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

      # Todo: config

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
      repo.config['core.bare'] = bare
      repo
    end

    private
    def get_head(path)


      get_object(data)
    end
  end
end