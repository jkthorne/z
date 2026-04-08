module Z
  class BitWriter
    @buffer : UInt64 = 0_u64
    @bits : Int32 = 0

    def initialize(@io : IO)
    end

    def write_bits(value : UInt32, n : Int32) : Nil
      @buffer |= value.to_u64 << @bits
      @bits += n
      flush_complete_bytes
    end

    def write_bit(b : Bool) : Nil
      write_bits(b ? 1_u32 : 0_u32, 1)
    end

    def write_bits_reversed(value : UInt32, n : Int32) : Nil
      reversed = 0_u32
      v = value
      n.times do
        reversed = (reversed << 1) | (v & 1)
        v >>= 1
      end
      write_bits(reversed, n)
    end

    def align_to_byte : Nil
      if @bits & 7 != 0
        pad = 8 - (@bits & 7)
        write_bits(0_u32, pad)
      end
    end

    def write_bytes(slice : Bytes) : Nil
      align_to_byte
      flush_all
      @io.write(slice)
    end

    def flush : Nil
      align_to_byte
      flush_all
    end

    def flush_all : Nil
      while @bits >= 8
        @io.write_byte((@buffer & 0xFF).to_u8)
        @buffer >>= 8
        @bits -= 8
      end
    end

    private def flush_complete_bytes : Nil
      while @bits >= 8
        @io.write_byte((@buffer & 0xFF).to_u8)
        @buffer >>= 8
        @bits -= 8
      end
    end
  end
end
