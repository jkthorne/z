require "../../spec_helper"
require "digest/crc32"

describe Z::CRC32 do
  it "returns 0 for empty data" do
    Z::CRC32.checksum(Bytes.empty).should eq(0_u32)
  end

  it "computes checksum for known string" do
    data = "123456789".to_slice
    # Known CRC-32 of "123456789" is 0xCBF43926
    Z::CRC32.checksum(data).should eq(0xCBF43926_u32)
  end

  it "matches Crystal stdlib for arbitrary data" do
    data = "Hello, World!".to_slice
    expected = Digest::CRC32.checksum(data)
    Z::CRC32.checksum(data).should eq(expected)
  end

  it "matches Crystal stdlib for large data" do
    data = Bytes.new(10000) { |i| (i % 256).to_u8 }
    expected = Digest::CRC32.checksum(data)
    Z::CRC32.checksum(data).should eq(expected)
  end

  it "supports incremental update" do
    part1 = "Hello, ".to_slice
    part2 = "World!".to_slice
    full = "Hello, World!".to_slice

    crc = Z::CRC32.update(part1, Z::CRC32.initial)
    crc = Z::CRC32.update(part2, crc)
    Z::CRC32.finalize(crc).should eq(Z::CRC32.checksum(full))
  end
end
