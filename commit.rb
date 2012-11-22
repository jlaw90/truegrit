require_relative 'author'
require_relative 'store'
require_relative 'util'

module TrueGrit
  class Commit
    attr_reader :repo, :author, :committer, :author_time, :commit_time, :message, :sha

    def initialize(repo, tree, parents, author, committer, author_time, commit_time, message, sha=nil)
      @repo = repo
      @tree = tree
      @parents = parents
      @author = author
      @committer = committer
      @author_time = author_time
      @commit_time = commit_time
      @message = message
      @sha = sha
    end

    def tree
      @repo.retrieve_object(@tree)
    end

    def parents
      @parents.map{|p| @repo.retrieve_object(p)}
    end

    def to_s
      "commit[#{sha}] {tree=#{@tree},parents=#{@parents}}"
    end

    def data
      res = "tree #@tree\n"
      @parents.each do |p|
        res += "parent #{p}\n"
      end
      res += "author #{@author.data} #{Util.time_format(@author_time)}\n"
      res += "committer #{@committer.data} #{Util.time_format(@commit_time)}\n"
      res += "\n" + message
      Util.crlf(res)
    end

    def add_ref(name, type=:head)
      # Todo: if it's a tag we may need to store an object...
      file = File.new(File.join(@repo.path, 'refs', "#{type.to_s}s", name), 'wb')
      sha = @repo.store_object(self)
      file.write("#{sha}\n")
      file.flush
      file.close
      sha
    end

    def checkout(path)
      tree.checkout(path)
    end

    def self.read(data, repo, sha)
      header = true
      tree= author= committer= author_time= commit_time = nil
      parents = []
      message = ''
      data.each_line do |line|
        line.chomp!
        if line.length == 0
          header = false
          next
        end
        if header
          type, data = line.split(' ', 2)
          case type
            when 'tree'
              tree = ShaHash.from_s(data)
            when 'parent'
              parents << ShaHash.from_s(data)
            when 'author'
              author, author_time = parse_author_line(data)
            when 'committer'
              committer, commit_time = parse_author_line(data)
            else
              raise 'Unexpected type in commit object: ' + type
          end
        else
          message += "#{line}\n"
        end
      end
      message.chop!

      Commit.new(repo, tree, parents, author, committer, author_time, commit_time, message, sha)
    end

    private
    def self.parse_author_line(data)
      parts = data.split ' '
      return Author.read(parts[0..-3].join(' ')), Util.time_parse(parts[-2], parts[-1])
    end
  end
end