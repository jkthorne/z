module Z
  class BitReader
    INPUT_BUFFER_SIZE = 8192

    @buffer : UInt64 = 0_u64
    @bits : Int32 = 0

    @input : Bytes = Bytes.new(INPUT_BUFFER_SIZE)
    @input_pos : Int32 = 0
    @input_len : Int32 = 0

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
        byte = read_input_byte
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
      # Drain input buffer next
      remaining_input = @input_len - @input_pos
      if remaining_input > 0 && pos < slice.size
        chunk = {remaining_input, slice.size - pos}.min
        slice[pos, chunk].copy_from(@input[@input_pos, chunk])
        @input_pos += chunk
        pos += chunk
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

    # Read a byte from the post-deflate stream (used by format wrappers for trailers).
    # First drains any byte-aligned bits in the bit buffer, then the input buffer,
    # then falls back to IO.
    def read_trailer_byte : UInt8?
      align_to_byte
      if @bits >= 8
        value = (@buffer & 0xFF).to_u8
        @buffer >>= 8
        @bits -= 8
        return value
      end
      @bits = 0
      @buffer = 0_u64
      if @input_pos < @input_len
        byte = @input[@input_pos]
        @input_pos += 1
        return byte
      end
      @io.read_byte
    end

    @eof : Bool = false
    @eof_padded : Bool = false

    private def ensure_bits(n : Int32) : Nil
      return if @bits >= n

      # Fast path: bulk-load bytes from input buffer into bit buffer
      avail = @input_len - @input_pos
      if avail >= 8 && @bits <= 56
        # Load 8 bytes at once via pointer, shift into buffer
        ptr = (@input.to_unsafe + @input_pos).as(Pointer(UInt64))
        word = ptr.value
        @buffer |= word << @bits
        consumed = (64 - @bits) >> 3
        @input_pos += consumed
        @bits += consumed << 3
        return if @bits >= n
      elsif avail > 0
        while @bits < n && @input_pos < @input_len
          @buffer |= @input[@input_pos].to_u64 << @bits
          @input_pos += 1
          @bits += 8
        end
        return if @bits >= n
      end

      # Need more data — refill from IO
      while @bits < n
        if @input_pos < @input_len
          @buffer |= @input[@input_pos].to_u64 << @bits
          @input_pos += 1
          @bits += 8
        elsif @eof
          if @eof_padded
            raise Z::Error.new("Unexpected end of input")
          end
          # Pad with zeros for final Huffman decode (DEFLATE streams are byte-padded)
          @eof_padded = true
          @buffer |= 0_u64 << @bits
          @bits += 8
        else
          refill_input_buffer
        end
      end
    end

    private def refill_input_buffer : Nil
      count = @io.read(@input)
      if count == 0
        @eof = true
      end
      @input_pos = 0
      @input_len = count
    end

    private def read_input_byte : UInt8?
      if @input_pos < @input_len
        byte = @input[@input_pos]
        @input_pos += 1
        return byte
      end
      refill_input_buffer
      if @input_pos < @input_len
        byte = @input[@input_pos]
        @input_pos += 1
        byte
      else
        nil
      end
    end
  end
end
