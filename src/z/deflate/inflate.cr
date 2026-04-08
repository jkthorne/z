module Z
  module Deflate
    class Inflater
      enum State
        BlockHeader
        StoredBlockInit
        StoredBlockCopy
        DecodeSymbols
        Finished
      end

      # Buffer size: 32KB window + 32KB output space
      BUFFER_SIZE = WINDOW_SIZE * 2

      @reader : BitReader
      @state : State = State::BlockHeader
      @final_block : Bool = false

      # Unified buffer serves as both sliding window and output accumulator.
      # Data is decoded into @buf starting at @buf_pos. The last WINDOW_SIZE
      # bytes before @buf_pos form the sliding window for back-references.
      # When @buf_pos reaches BUFFER_SIZE, we slide the window down.
      @buf : Bytes = Bytes.new(BUFFER_SIZE)
      @buf_pos : Int32 = 0         # Next write position
      @buf_read_pos : Int32 = 0    # Next position to flush to caller
      @total_out : Int64 = 0_i64   # Total bytes output (for distance validation)

      # Current block trees
      @literal_tree : Huffman::Tree?
      @distance_tree : Huffman::Tree?

      # Stored block state
      @stored_remaining : Int32 = 0

      # Back-reference state (partial copy across read calls)
      @copy_length : Int32 = 0
      @copy_distance : Int32 = 0

      def initialize(io : IO)
        @reader = BitReader.new(io)
      end

      # Expose the bit reader for trailer reading by format wrappers
      def bit_reader : BitReader
        @reader
      end

      def read(output : Bytes) : Int32
        return 0 if @state == State::Finished && @copy_length == 0 && @buf_read_pos >= @buf_pos
        written = 0

        while written < output.size
          # First, flush any buffered decoded data to the caller
          buffered = @buf_pos - @buf_read_pos
          if buffered > 0
            chunk = {buffered, output.size - written}.min
            output[written, chunk].copy_from(@buf[@buf_read_pos, chunk])
            @buf_read_pos += chunk
            written += chunk
            # Slide window when all buffered data has been consumed
            if @buf_read_pos == @buf_pos
              ensure_buf_space
            end
            next if written >= output.size
          end

          # Make sure there's space to decode into
          ensure_buf_space if @buf_pos >= BUFFER_SIZE

          # Decode more data into our internal buffer
          if @copy_length > 0
            emit_copy
            next
          end

          case @state
          when .block_header?
            read_block_header
          when .stored_block_init?
            init_stored_block
          when .stored_block_copy?
            copy_stored
          when .decode_symbols?
            decode_symbols
          when .finished?
            break
          end
        end

        written
      end

      private def read_block_header : Nil
        @final_block = @reader.read_bit
        btype = @reader.read_bits(2)

        case btype
        when 0 # Stored
          @state = State::StoredBlockInit
        when 1 # Fixed Huffman
          @literal_tree = fixed_literal_tree
          @distance_tree = fixed_distance_tree
          @state = State::DecodeSymbols
        when 2 # Dynamic Huffman
          read_dynamic_tables
          @state = State::DecodeSymbols
        else
          raise Deflate::Error.new("Invalid block type: #{btype}")
        end
      end

      private def init_stored_block : Nil
        @reader.align_to_byte
        len = @reader.read_bits(16).to_i32
        nlen = @reader.read_bits(16).to_i32
        if len != (nlen ^ 0xFFFF)
          raise Deflate::Error.new("Stored block length mismatch: len=#{len}, nlen=#{nlen}")
        end
        @stored_remaining = len
        @state = State::StoredBlockCopy
      end

      private def copy_stored : Nil
        if @stored_remaining == 0
          @state = @final_block ? State::Finished : State::BlockHeader
          return
        end

        ensure_buf_space
        can_write = {BUFFER_SIZE - @buf_pos, @stored_remaining}.min
        return if can_write == 0

        buf = @buf[@buf_pos, can_write]
        @reader.read_bytes(buf)
        @buf_pos += can_write
        @total_out += can_write
        @stored_remaining -= can_write

        if @stored_remaining == 0
          @state = @final_block ? State::Finished : State::BlockHeader
        end
      end

      private def decode_symbols : Nil
        literal_tree = @literal_tree.not_nil!
        distance_tree = @distance_tree.not_nil!
        buf_ptr = @buf.to_unsafe

        while @buf_pos < BUFFER_SIZE
          symbol = literal_tree.decode(@reader)

          if symbol < 256
            # Literal byte — write directly to buffer
            buf_ptr[@buf_pos] = symbol.to_u8
            @buf_pos += 1
            @total_out += 1
          elsif symbol == END_OF_BLOCK
            @state = @final_block ? State::Finished : State::BlockHeader
            break
          else
            # Length/distance pair
            length = decode_length(symbol)
            dist_code = distance_tree.decode(@reader)
            distance = decode_distance(dist_code)

            if distance > @total_out
              raise Deflate::Error.new("Invalid back-reference distance #{distance} exceeds output #{@total_out}")
            end

            @copy_length = length
            @copy_distance = distance
            emit_copy
            break if @buf_pos >= BUFFER_SIZE
          end
        end
      end

      private def emit_copy : Nil
        buf_ptr = @buf.to_unsafe

        while @copy_length > 0 && @buf_pos < BUFFER_SIZE
          src_pos = @buf_pos - @copy_distance
          avail = {BUFFER_SIZE - @buf_pos, @copy_length}.min

          if @copy_distance >= @copy_length
            # Non-overlapping: bulk copy
            @buf[@buf_pos, avail].copy_from(@buf[src_pos, avail])
            @buf_pos += avail
            @total_out += avail
            @copy_length -= avail
          elsif @copy_distance == 1
            # RLE: single byte repeated — fill with memset
            byte = buf_ptr[src_pos]
            @buf[@buf_pos, avail].fill(byte)
            @buf_pos += avail
            @total_out += avail
            @copy_length -= avail
          elsif @copy_distance < 8
            # Small overlapping: expand pattern then bulk copy
            # First, expand the pattern to at least 8 bytes
            pattern_start = @buf_pos
            dist = @copy_distance
            # Copy initial pattern bytes
            count = {dist, avail}.min
            count.times do |i|
              buf_ptr[@buf_pos + i] = buf_ptr[src_pos + i]
            end
            # Double the pattern until we have enough
            copied = count
            while copied < avail
              chunk = {copied, avail - copied}.min
              @buf[@buf_pos + copied, chunk].copy_from(@buf[pattern_start, chunk])
              copied += chunk
            end
            @buf_pos += avail
            @total_out += avail
            @copy_length -= avail
          else
            # Overlapping with large distance: copy in distance-sized chunks
            while @copy_length > 0 && @buf_pos < BUFFER_SIZE
              chunk = {@copy_distance, @copy_length, BUFFER_SIZE - @buf_pos}.min
              src = @buf_pos - @copy_distance
              @buf[@buf_pos, chunk].copy_from(@buf[src, chunk])
              @buf_pos += chunk
              @total_out += chunk
              @copy_length -= chunk
            end
          end
        end
      end

      # Ensure there's space in the buffer. If full, slide the window down.
      private def ensure_buf_space : Nil
        return if @buf_pos < BUFFER_SIZE

        # Keep the last WINDOW_SIZE bytes as the sliding window
        keep = {WINDOW_SIZE, @buf_pos}.min
        if keep > 0
          @buf.copy_from(@buf[(@buf_pos - keep), keep])
        end
        @buf_read_pos = {0, @buf_read_pos - (@buf_pos - keep)}.max
        @buf_pos = keep
      end

      private def decode_length(symbol : UInt16) : Int32
        index = symbol.to_i - 257
        if index < 0 || index >= Huffman::LENGTH_BASE.size
          raise Deflate::Error.new("Invalid length code: #{symbol}")
        end
        base = Huffman::LENGTH_BASE[index]
        extra = Huffman::LENGTH_EXTRA[index]
        base + (extra > 0 ? @reader.read_bits(extra).to_i32 : 0)
      end

      private def decode_distance(code : UInt16) : Int32
        index = code.to_i
        if index < 0 || index >= Huffman::DISTANCE_BASE.size
          raise Deflate::Error.new("Invalid distance code: #{code}")
        end
        base = Huffman::DISTANCE_BASE[index]
        extra = Huffman::DISTANCE_EXTRA[index]
        base + (extra > 0 ? @reader.read_bits(extra).to_i32 : 0)
      end

      private def read_dynamic_tables : Nil
        hlit = @reader.read_bits(5).to_i32 + 257
        hdist = @reader.read_bits(5).to_i32 + 1
        hclen = @reader.read_bits(4).to_i32 + 4

        # Read code length code lengths
        cl_lengths = Array(UInt8).new(19, 0_u8)
        hclen.times do |i|
          cl_lengths[Huffman::CODE_LENGTH_ORDER[i]] = @reader.read_bits(3).to_u8
        end

        cl_tree = Huffman::Tree.new(cl_lengths, 19)

        # Decode literal/length + distance code lengths
        total = hlit + hdist
        lengths = Array(UInt8).new(total, 0_u8)
        i = 0
        while i < total
          symbol = cl_tree.decode(@reader)
          case symbol
          when 0..15
            lengths[i] = symbol.to_u8
            i += 1
          when 16
            # Repeat previous 3-6 times
            raise Deflate::Error.new("Code 16 with no previous length") if i == 0
            repeat = 3 + @reader.read_bits(2).to_i32
            val = lengths[i - 1]
            repeat.times do
              raise Deflate::Error.new("Code length overflow") if i >= total
              lengths[i] = val
              i += 1
            end
          when 17
            # Repeat 0 for 3-10 times
            repeat = 3 + @reader.read_bits(3).to_i32
            repeat.times do
              raise Deflate::Error.new("Code length overflow") if i >= total
              lengths[i] = 0_u8
              i += 1
            end
          when 18
            # Repeat 0 for 11-138 times
            repeat = 11 + @reader.read_bits(7).to_i32
            repeat.times do
              raise Deflate::Error.new("Code length overflow") if i >= total
              lengths[i] = 0_u8
              i += 1
            end
          else
            raise Deflate::Error.new("Invalid code length symbol: #{symbol}")
          end
        end

        @literal_tree = Huffman::Tree.new(lengths[0, hlit], hlit)
        @distance_tree = Huffman::Tree.new(lengths[hlit, hdist], hdist)
      end

      @@fixed_literal_tree : Huffman::Tree?
      @@fixed_distance_tree : Huffman::Tree?

      private def fixed_literal_tree : Huffman::Tree
        @@fixed_literal_tree ||= Huffman::Tree.new(Huffman::FIXED_LITERAL_LENGTHS.to_slice, 288)
      end

      private def fixed_distance_tree : Huffman::Tree
        @@fixed_distance_tree ||= Huffman::Tree.new(Huffman::FIXED_DISTANCE_LENGTHS.to_slice, 32)
      end
    end
  end
end
