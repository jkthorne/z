require "../../spec_helper"

describe Z::BitReader do
  it "reads individual bits LSB-first" do
    io = IO::Memory.new(Bytes[0b10110001])
    reader = Z::BitReader.new(io)

    reader.read_bit.should eq(true)   # bit 0
    reader.read_bit.should eq(false)  # bit 1
    reader.read_bit.should eq(false)  # bit 2
    reader.read_bit.should eq(false)  # bit 3
    reader.read_bit.should eq(true)   # bit 4
    reader.read_bit.should eq(true)   # bit 5
    reader.read_bit.should eq(false)  # bit 6
    reader.read_bit.should eq(true)   # bit 7
  end

  it "reads multi-bit values" do
    io = IO::Memory.new(Bytes[0b11010110])
    reader = Z::BitReader.new(io)

    reader.read_bits(3).should eq(0b110)  # bits 0-2
    reader.read_bits(5).should eq(0b11010) # bits 3-7
  end

  it "reads across byte boundaries" do
    io = IO::Memory.new(Bytes[0xFF, 0x01])
    reader = Z::BitReader.new(io)

    reader.read_bits(4).should eq(0xF)
    reader.read_bits(8).should eq(0x1F)  # 4 bits from first byte + 4 from second
  end

  it "aligns to byte boundary" do
    io = IO::Memory.new(Bytes[0xFF, 0xAB])
    reader = Z::BitReader.new(io)

    reader.read_bits(3)
    reader.align_to_byte
    reader.read_bits(8).should eq(0xAB)
  end

  it "reads raw bytes after alignment" do
    io = IO::Memory.new(Bytes[0xFF, 0x01, 0x02, 0x03])
    reader = Z::BitReader.new(io)

    reader.read_bits(3)
    reader.align_to_byte
    buf = Bytes.new(3)
    reader.read_bytes(buf)
    buf.should eq(Bytes[0x01, 0x02, 0x03])
  end

  it "peeks without consuming" do
    io = IO::Memory.new(Bytes[0b10110001])
    reader = Z::BitReader.new(io)

    reader.peek_bits(4).should eq(0b0001)
    reader.peek_bits(4).should eq(0b0001)
    reader.read_bits(4).should eq(0b0001)
    reader.read_bits(4).should eq(0b1011)
  end

  it "raises on unexpected EOF after padding exhausted" do
    io = IO::Memory.new(Bytes.empty)
    reader = Z::BitReader.new(io)

    # First read returns zero-padded bits (EOF padding for DEFLATE)
    reader.read_bits(8)
    # Second read beyond the single zero-pad should raise
    expect_raises(Z::Error, "Unexpected end of input") do
      reader.read_bits(8)
    end
  end
end
