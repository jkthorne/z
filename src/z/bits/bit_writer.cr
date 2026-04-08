module Z
  class BitWriter
    OUTPUT_BUFFER_SIZE = 4096

    @buffer : UInt64 = 0_u64
    @bits : Int32 = 0
    @out_buf : Bytes = Bytes.new(OUTPUT_BUFFER_SIZE)
    @out_pos : Int32 = 0

    def initialize(@io : IO)
    end

    @[AlwaysInline]
    def write_bits(value : UInt32, n : Int32) : Nil
      @buffer |= value.to_u64 << @bits
      @bits += n
      flush_complete_bytes if @bits >= 32
    end

    def write_bit(b : Bool) : Nil
      write_bits(b ? 1_u32 : 0_u32, 1)
    end

    def write_bits_reversed(value : UInt32, n : Int32) : Nil
      write_bits(Huffman.reverse_bits(value, n), n)
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
      flush_out_buf
      @io.write(slice)
    end

    def flush : Nil
      align_to_byte
      flush_all
      flush_out_buf
    end

    def flush_all : Nil
      flush_complete_bytes
      flush_out_buf
    end

    @[AlwaysInline]
    private def flush_complete_bytes : Nil
      while @bits >= 8
        @out_buf[@out_pos] = (@buffer & 0xFF).to_u8
        @out_pos += 1
        @buffer >>= 8
        @bits -= 8
        if @out_pos >= OUTPUT_BUFFER_SIZE
          flush_out_buf
        end
      end
    end

    private def flush_out_buf : Nil
      if @out_pos > 0
        @io.write(@out_buf[0, @out_pos])
        @out_pos = 0
      end
    end
  end
end
