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

      @reader : BitReader
      @state : State = State::BlockHeader
      @final_block : Bool = false
      @window : Bytes = Bytes.new(WINDOW_SIZE)
      @window_pos : Int32 = 0
      @window_used : Int32 = 0

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

      def read(output : Bytes) : Int32
        return 0 if @state == State::Finished && @copy_length == 0
        written = 0

        while written < output.size
          # Handle pending back-reference copy
          if @copy_length > 0
            written += emit_copy(output, written)
            next if @copy_length > 0
          end

          case @state
          when .block_header?
            read_block_header
          when .stored_block_init?
            init_stored_block
          when .stored_block_copy?
            written += copy_stored(output, written)
          when .decode_symbols?
            written += decode_symbols(output, written)
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

      private def copy_stored(output : Bytes, offset : Int32) : Int32
        if @stored_remaining == 0
          @state = @final_block ? State::Finished : State::BlockHeader
          return 0
        end

        can_write = {output.size - offset, @stored_remaining}.min
        return 0 if can_write == 0

        buf = output[offset, can_write]
        @reader.read_bytes(buf)
        buf.each do |byte|
          @window[@window_pos] = byte
          @window_pos = (@window_pos + 1) & WINDOW_MASK
          @window_used = {@window_used + 1, WINDOW_SIZE}.min
        end
        @stored_remaining -= can_write

        if @stored_remaining == 0
          @state = @final_block ? State::Finished : State::BlockHeader
        end

        can_write
      end

      private def decode_symbols(output : Bytes, offset : Int32) : Int32
        literal_tree = @literal_tree.not_nil!
        distance_tree = @distance_tree.not_nil!
        written = 0

        while offset + written < output.size
          symbol = literal_tree.decode(@reader)

          if symbol < 256
            # Literal byte
            byte = symbol.to_u8
            output[offset + written] = byte
            @window[@window_pos] = byte
            @window_pos = (@window_pos + 1) & WINDOW_MASK
            @window_used = {@window_used + 1, WINDOW_SIZE}.min
            written += 1
          elsif symbol == END_OF_BLOCK
            @state = @final_block ? State::Finished : State::BlockHeader
            break
          else
            # Length/distance pair
            length = decode_length(symbol)
            dist_code = distance_tree.decode(@reader)
            distance = decode_distance(dist_code)

            if distance > @window_used
              raise Deflate::Error.new("Invalid back-reference distance #{distance} exceeds window #{@window_used}")
            end

            @copy_length = length
            @copy_distance = distance
            written += emit_copy(output, offset + written)
            break if @copy_length > 0  # Partial copy, need more output space
          end
        end

        written
      end

      private def emit_copy(output : Bytes, offset : Int32) : Int32
        written = 0
        while @copy_length > 0 && offset + written < output.size
          avail = {output.size - (offset + written), @copy_length}.min
          src_pos = (@window_pos - @copy_distance) & WINDOW_MASK

          if @copy_distance >= @copy_length
            # Non-overlapping: bulk copy from window
            # Handle window wrap-around
            chunk = {avail, WINDOW_SIZE - src_pos}.min
            output[offset + written, chunk].copy_from(@window[src_pos, chunk])

            # Update window with copied bytes
            if @window_pos + chunk <= WINDOW_SIZE
              @window[@window_pos, chunk].copy_from(output[offset + written, chunk])
              @window_pos = (@window_pos + chunk) & WINDOW_MASK
            else
              # Window write wraps around
              first = WINDOW_SIZE - @window_pos
              @window[@window_pos, first].copy_from(output[offset + written, first])
              @window[0, chunk - first].copy_from(output[offset + written + first, chunk - first])
              @window_pos = chunk - first
            end
            @window_used = {@window_used + chunk, WINDOW_SIZE}.min
            @copy_length -= chunk
            written += chunk
          else
            # Overlapping: byte-at-a-time (required for repeating patterns)
            byte = @window[src_pos]
            output[offset + written] = byte
            @window[@window_pos] = byte
            @window_pos = (@window_pos + 1) & WINDOW_MASK
            @window_used = {@window_used + 1, WINDOW_SIZE}.min
            @copy_length -= 1
            written += 1
          end
        end
        written
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
