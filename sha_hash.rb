require 'digest/sha1'

class ShaHash
  attr_reader :sha, :hash

  def initialize(sha)
    if sha.nil? or sha.length != 20
      raise 'Invalid hash!'
    end
    @sha = sha
    @hash = sha.hash
  end

  def to_s
    @sha.chars.map {|c| sprintf("%2.2x", c.ord)}.join
  end

  def eql?(other)
    return false if other.nil?
    other.sha == @sha
  end

  def ==(other)
    eql?(other)
  end

  def self.calculate(data)
    ShaHash.new(hash(data))
  end

  def self.from_s(s)
    ShaHash.new([s].pack('H*'))
  end

  def self.hash(data)
    Digest::SHA1.digest(data)
  end
end