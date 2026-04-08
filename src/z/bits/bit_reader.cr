module Z
  class BitReader
    @buffer : UInt64 = 0_u64
    @bits : Int32 = 0

    def initialize(@io : IO)
    end

    def read_bits(n : Int32) : UInt32
      ensure_bits(n)
      value = (@buffer & ((1_u64 << n) - 1)).to_u32
      @buffer >>= n
      @bits -= n
      value
    end

    def read_bit : Bool
      read_bits(1) == 1
    end

    def peek_bits(n : Int32) : UInt32
      ensure_bits(n)
      (@buffer & ((1_u64 << n) - 1)).to_u32
    end

    def drop_bits(n : Int32) : Nil
      @buffer >>= n
      @bits -= n
    end

    def align_to_byte : Nil
      discard = @bits & 7
      if discard > 0
        @buffer >>= discard
        @bits -= discard
      end
    end

    def read_byte : UInt8
      align_to_byte
      if @bits >= 8
        value = (@buffer & 0xFF).to_u8
        @buffer >>= 8
        @bits -= 8
        value
      else
        @bits = 0
        @buffer = 0
        byte = @io.read_byte
        raise Z::Error.new("Unexpected end of input") if byte.nil?
        byte
      end
    end

    def read_bytes(slice : Bytes) : Nil
      align_to_byte
      # Drain buffered bytes first
      pos = 0
      while pos < slice.size && @bits >= 8
        slice[pos] = (@buffer & 0xFF).to_u8
        @buffer >>= 8
        @bits -= 8
        pos += 1
      end
      # Read remaining directly from IO
      while pos < slice.size
        count = @io.read(slice[pos..])
        raise Z::Error.new("Unexpected end of input") if count == 0
        pos += count
      end
    end

    def bits_buffered : Int32
      @bits
    end

    @eof : Bool = false

    private def ensure_bits(n : Int32) : Nil
      while @bits < n
        if @eof
          raise Z::Error.new("Unexpected end of input")
        end
        byte = @io.read_byte
        if byte.nil?
          @eof = true
          # Pad with zeros for final Huffman decode (DEFLATE streams are byte-padded)
          @buffer |= 0_u64 << @bits
          @bits += 8
        else
          @buffer |= byte.to_u64 << @bits
          @bits += 8
        end
      end
    end
  end
end
