require "../../spec_helper"

describe Z::Huffman::Encoder do
  it "builds valid codes for simple frequencies" do
    freqs = [10, 5, 3, 1]  # 4 symbols
    encoder = Z::Huffman::Encoder.new(freqs)

    # All active symbols should have non-zero lengths
    encoder.lengths[0].should be > 0
    encoder.lengths[1].should be > 0
    encoder.lengths[2].should be > 0
    encoder.lengths[3].should be > 0

    # Most frequent symbol should have shortest code
    encoder.lengths[0].should be <= encoder.lengths[3]
  end

  it "handles single symbol" do
    freqs = [0, 0, 5, 0]
    encoder = Z::Huffman::Encoder.new(freqs)

    encoder.lengths[2].should eq(1)
    encoder.lengths[0].should eq(0)
    encoder.lengths[1].should eq(0)
    encoder.lengths[3].should eq(0)
  end

  it "handles all-zero frequencies" do
    freqs = [0, 0, 0]
    encoder = Z::Huffman::Encoder.new(freqs)

    encoder.lengths.each { |l| l.should eq(0) }
  end

  it "respects max_bits constraint" do
    # Create frequencies that would naturally produce deep trees
    freqs = Array.new(256) { |i| (i + 1) }
    encoder = Z::Huffman::Encoder.new(freqs, max_bits: 15)

    encoder.lengths.each do |len|
      len.should be <= 15 if len > 0
    end
  end

  it "round-trips through encoder and tree decoder" do
    freqs = [100, 50, 25, 12, 6, 3, 1]
    encoder = Z::Huffman::Encoder.new(freqs)

    # Encode all symbols
    io = IO::Memory.new
    writer = Z::BitWriter.new(io)
    freqs.size.times { |sym| encoder.encode(writer, sym) }
    writer.write_bits(0_u32, 16)  # Padding for peek
    writer.flush

    # Build decoder tree from the same lengths
    tree = Z::Huffman::Tree.new(encoder.lengths, encoder.lengths.size)

    # Decode and verify
    io.rewind
    reader = Z::BitReader.new(io)
    freqs.size.times do |sym|
      tree.decode(reader).should eq(sym.to_u16)
    end
  end

  it "produces valid canonical Huffman codes" do
    freqs = [5, 10, 20, 1, 1, 1, 1, 1]
    encoder = Z::Huffman::Encoder.new(freqs)

    # Verify Kraft inequality: sum of 2^(-length) <= 1
    kraft_sum = 0.0
    encoder.lengths.each do |len|
      kraft_sum += 1.0 / (1 << len) if len > 0
    end
    kraft_sum.should be <= 1.0 + 1e-10
  end
end
