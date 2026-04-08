require "../../spec_helper"
require "compress/gzip"

describe Z::Gzip::Reader do
  it "decompresses data from stdlib Compress::Gzip::Writer" do
    original = "Hello, gzip World! Compression is working great."

    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "decompresses empty data" do
    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) { }
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq("")
  end

  it "decompresses larger data" do
    original = String.build do |sb|
      500.times { |i| sb << "Line #{i}: gzip test data with various content.\n" }
    end

    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "reads header metadata" do
    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.print "test"
    end
    compressed.rewind

    reader = Z::Gzip::Reader.new(compressed)
    reader.header.should_not be_nil
    reader.gets_to_end
    reader.close
  end

  it "raises on invalid magic bytes" do
    io = IO::Memory.new(Bytes[0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    expect_raises(Z::Gzip::Error, "Invalid gzip magic") do
      Z::Gzip::Reader.new(io)
    end
  end

  it "raises on reserved FLG bits set" do
    # Build a minimal gzip header with reserved bit 5 set
    io = IO::Memory.new
    io.write_byte(0x1F_u8) # ID1
    io.write_byte(0x8B_u8) # ID2
    io.write_byte(0x08_u8) # CM
    io.write_byte(0x20_u8) # FLG with reserved bit 5 set
    4.times { io.write_byte(0_u8) } # MTIME
    io.write_byte(0_u8) # XFL
    io.write_byte(0xFF_u8) # OS
    io.rewind

    expect_raises(Z::Gzip::Error, "Reserved FLG bits") do
      Z::Gzip::Reader.new(io)
    end
  end

  it "verifies FHCRC when present" do
    # Compress data with Z, then manually construct a stream with FHCRC
    original = "FHCRC test data"

    # Build gzip header with FHCRC flag
    io = IO::Memory.new
    header_bytes = IO::Memory.new

    # Fixed header (10 bytes)
    header_bytes.write_byte(0x1F_u8) # ID1
    header_bytes.write_byte(0x8B_u8) # ID2
    header_bytes.write_byte(0x08_u8) # CM
    header_bytes.write_byte(0x02_u8) # FLG = FHCRC
    4.times { header_bytes.write_byte(0_u8) } # MTIME
    header_bytes.write_byte(0_u8)    # XFL
    header_bytes.write_byte(0xFF_u8) # OS

    # Compute CRC-32 of header bytes
    header_bytes.rewind
    header_data = header_bytes.to_slice
    header_crc = Z::CRC32.checksum(header_data)
    crc16 = (header_crc & 0xFFFF).to_u16

    # Write full stream: header + CRC16 + compressed data + trailer
    io.write(header_data)
    io.write_byte((crc16 & 0xFF).to_u8)
    io.write_byte(((crc16 >> 8) & 0xFF).to_u8)

    # Get compressed deflate data from a normal gzip stream
    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { |w| w.print original }
    compressed.rewind
    all_bytes = compressed.to_slice
    # Skip the 10-byte header, take everything after it (deflate data + trailer)
    io.write(all_bytes[10..])

    io.rewind
    result = Z::Gzip::Reader.open(io) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "raises on invalid FHCRC" do
    io = IO::Memory.new

    # Fixed header with FHCRC flag
    io.write_byte(0x1F_u8) # ID1
    io.write_byte(0x8B_u8) # ID2
    io.write_byte(0x08_u8) # CM
    io.write_byte(0x02_u8) # FLG = FHCRC
    4.times { io.write_byte(0_u8) } # MTIME
    io.write_byte(0_u8)    # XFL
    io.write_byte(0xFF_u8) # OS
    # Write wrong CRC16
    io.write_byte(0xFF_u8)
    io.write_byte(0xFF_u8)

    io.rewind
    expect_raises(Z::Gzip::Error, "Header CRC16 mismatch") do
      Z::Gzip::Reader.new(io)
    end
  end

  it "decompresses random data" do
    random = Random.new(123)
    original = Bytes.new(3000) { random.rand(256).to_u8 }

    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.write(original)
    end
    compressed.rewind

    result = IO::Memory.new
    Z::Gzip::Reader.open(compressed) do |r|
      IO.copy(r, result)
    end
    result.rewind
    result.to_slice.should eq(original)
  end
end
