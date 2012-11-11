require "rspec"
require_relative 'spec_helper'

describe "SHA1 Hash" do

  before(:all) do
    @hash_data = ?d*500
    @hash = ShaHash.calculate(@hash_data)
    @hash_dup = ShaHash.calculate(@hash_data)
  end

  it "should have equality" do
    @hash.should eql @hash_dup
    @hash_dup.should eql @hash
  end

  it "should convert to/from strings correctly" do
    ShaHash.new(@hash.sha).should eql @hash
    ShaHash.from_s(@hash.to_s).should eql @hash
  end

  it "should correctly hash itself" do
    @hash.hash.should eql @hash_dup.hash
  end
end