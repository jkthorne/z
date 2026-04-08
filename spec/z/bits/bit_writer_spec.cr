require "../../spec_helper"

describe Z::BitWriter do
  it "writes individual bits LSB-first" do
    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    writer.write_bit(true)   # bit 0
    writer.write_bit(false)  # bit 1
    writer.write_bit(false)  # bit 2
    writer.write_bit(false)  # bit 3
    writer.write_bit(true)   # bit 4
    writer.write_bit(true)   # bit 5
    writer.write_bit(false)  # bit 6
    writer.write_bit(true)   # bit 7
    writer.flush

    io.rewind
    io.read_byte.should eq(0b10110001_u8)
  end

  it "writes multi-bit values" do
    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    writer.write_bits(0b110_u32, 3)
    writer.write_bits(0b11010_u32, 5)
    writer.flush

    io.rewind
    io.read_byte.should eq(0b11010110_u8)
  end

  it "writes across byte boundaries" do
    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    writer.write_bits(0xF_u32, 4)
    writer.write_bits(0x1F_u32, 8)
    writer.flush

    io.rewind
    io.read_byte.should eq(0xFF_u8)
    io.read_byte.should eq(0x01_u8)
  end

  it "round-trips with BitReader" do
    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    values = [{7_u32, 3}, {42_u32, 6}, {1023_u32, 10}, {0_u32, 1}, {255_u32, 8}]
    values.each { |v, n| writer.write_bits(v, n) }
    writer.flush

    io.rewind
    reader = Z::BitReader.new(io)

    values.each do |v, n|
      reader.read_bits(n).should eq(v)
    end
  end

  it "writes reversed bits" do
    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    # 0b1010 reversed in 4 bits = 0b0101
    writer.write_bits_reversed(0b1010_u32, 4)
    writer.write_bits(0_u32, 4)
    writer.flush

    io.rewind
    io.read_byte.should eq(0b00000101_u8)
  end
end
