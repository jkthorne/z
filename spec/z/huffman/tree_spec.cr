require "../../spec_helper"

describe Z::Huffman::Tree do
  it "decodes fixed literal codes correctly" do
    tree = Z::Huffman::Tree.new(Z::Huffman::FIXED_LITERAL_LENGTHS.to_slice, 288)

    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    # Symbol 65 ('A'): 8-bit fixed code = 0b00110000 + 65 = 0b01110001
    code_65 = 0b01110001_u32
    reversed = 0_u32
    c = code_65
    8.times do
      reversed = (reversed << 1) | (c & 1)
      c >>= 1
    end
    writer.write_bits(reversed, 8)

    # End of block (256): 7-bit code = 0b0000000
    writer.write_bits(0_u32, 7)

    # Padding so peek_bits(9) doesn't hit EOF
    writer.write_bits(0_u32, 16)
    writer.flush

    io.rewind
    reader = Z::BitReader.new(io)

    tree.decode(reader).should eq(65_u16)
    tree.decode(reader).should eq(256_u16)
  end

  it "decodes fixed distance codes" do
    tree = Z::Huffman::Tree.new(Z::Huffman::FIXED_DISTANCE_LENGTHS.to_slice, 32)

    io = IO::Memory.new
    writer = Z::BitWriter.new(io)

    # Distance code 0 = 0b00000 reversed = 0b00000
    writer.write_bits(0_u32, 5)
    # Distance code 5 = 0b00101 reversed = 0b10100
    writer.write_bits(0b10100_u32, 5)
    # Padding
    writer.write_bits(0_u32, 16)
    writer.flush

    io.rewind
    reader = Z::BitReader.new(io)

    tree.decode(reader).should eq(0_u16)
    tree.decode(reader).should eq(5_u16)
  end

  it "handles a simple custom tree" do
    # A = 1 bit (0), B = 2 bits (10), C = 2 bits (11)
    lengths = Slice[1_u8, 2_u8, 2_u8]
    tree = Z::Huffman::Tree.new(lengths, 3)

    io = IO::Memory.new
    writer = Z::BitWriter.new(io)
    # A (symbol 0): code=0, len=1, reversed=0
    writer.write_bits(0_u32, 1)
    # B (symbol 1): code=10, len=2, reversed=01
    writer.write_bits(0b01_u32, 2)
    # C (symbol 2): code=11, len=2, reversed=11
    writer.write_bits(0b11_u32, 2)
    # A again
    writer.write_bits(0_u32, 1)
    # Padding
    writer.write_bits(0_u32, 16)
    writer.flush

    io.rewind
    reader = Z::BitReader.new(io)

    tree.decode(reader).should eq(0_u16)
    tree.decode(reader).should eq(1_u16)
    tree.decode(reader).should eq(2_u16)
    tree.decode(reader).should eq(0_u16)
  end
end
