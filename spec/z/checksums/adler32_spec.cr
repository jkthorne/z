require "../../spec_helper"
require "digest/adler32"

describe Z::Adler32 do
  it "returns 1 for empty data" do
    Z::Adler32.checksum(Bytes.empty).should eq(1_u32)
  end

  it "computes checksum for 'Hello'" do
    data = "Hello".to_slice
    expected = Digest::Adler32.checksum(data)
    Z::Adler32.checksum(data).should eq(expected)
  end

  it "computes checksum for a single byte" do
    data = Bytes[0x41]
    expected = Digest::Adler32.checksum(data)
    Z::Adler32.checksum(data).should eq(expected)
  end

  it "computes checksum for larger data" do
    data = Bytes.new(10000) { |i| (i % 256).to_u8 }
    expected = Digest::Adler32.checksum(data)
    Z::Adler32.checksum(data).should eq(expected)
  end

  it "supports incremental update" do
    part1 = "Hello, ".to_slice
    part2 = "World!".to_slice
    full = "Hello, World!".to_slice

    adler = Z::Adler32.update(part1, Z::Adler32.initial)
    adler = Z::Adler32.update(part2, adler)
    adler.should eq(Z::Adler32.checksum(full))
  end

  it "handles data exceeding NMAX" do
    data = Bytes.new(6000) { |i| (i % 251).to_u8 }
    expected = Digest::Adler32.checksum(data)
    Z::Adler32.checksum(data).should eq(expected)
  end
end
