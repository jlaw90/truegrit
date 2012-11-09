require_relative 'author'
require_relative 'object_store'

module TrueGrit
  class Commit
    attr_reader :repo, :author, :committer, :author_time, :commit_time, :message

    def initialize(repo, tree, parent, author, committer, author_time, commit_time, message)
      @repo = repo
      @tree = tree
      @parent = parent
      @author = author
      @committer = committer
      @author_time = author_time
      @commit_time = commit_time
      @message = message
    end

    def tree
      @repo.get_object(@tree)
    end

    def parent
      @repo.get_object(@parent) unless @parent.nil?
    end

    def data
      res = "tree #@tree\n"
      res += "parent #@parent\n" unless @parent.nil?
      res += "author #{@author.data} #{Commit.time_str(@author_time)}\n"
      res += "committer #{@committer.data} #{Commit.time_str(@commit_time)}\n"
      res += "\n" + message
      Util.crlf(res)
    end

    def set_head(name)
      file = File.new(File.join(@repo.path, 'refs', 'heads', name), 'wb')
      sha = @repo.put_object(self)
      file.write(Util.crlf("#{sha}\n"))
      file.flush
      file.close
      sha
    end

    def checkout(path)
      tree.checkout(path)
    end

    def self.read(data, repo)
      header = true
      tree, parent, author, committer, author_time, commit_time = nil
      message = ''
      data.each_line do |line|
        line.chomp!
        if line.length == 0
          header = false
          next
        end
        if header
          type,data = line.split(' ', 2)
          case type
            when 'tree'
              tree = data
            when 'parent'
              parent = data
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

      Commit.new(repo, tree, parent, author, committer, author_time, commit_time, message)
    end

    private
    def self.parse_author_line(data)
      parts = data.split ' '
      return Author.read(parts[0..-3].join(' ')), parse_time(parts[-2], parts[-1])
    end

    def self.parse_time(secs, tz)
      t = Time.at(secs.to_i) + (60 * 60 * tz.to_i)
    end

    def self.time_str(time)
      time.strftime("%s %z")
    end
  end
end