require "rspec"
require_relative 'spec_helper'

describe "pack_time" do
  it "should pack and unpack the time correctly" do
    tt = Time.now
    packed = TrueGrit::Util.time_pack(tt)
    unpacked = TrueGrit::Util.time_unpack(packed)
    unpacked.to_i.should eql tt.to_i
  end
end