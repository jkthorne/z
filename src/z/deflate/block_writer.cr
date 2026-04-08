module Z
  module Deflate
    class BlockWriter
      MAX_BLOCK_TOKENS = 16384

      @tokens : Array(Token)
      @writer : BitWriter
      @level : Int32
      @lit_freq : Array(Int32)
      @dist_freq : Array(Int32)

      def initialize(@writer : BitWriter, @level : Int32 = DEFAULT_COMPRESSION)
        @tokens = Array(Token).new(MAX_BLOCK_TOKENS)
        @lit_freq = Array(Int32).new(286, 0)
        @dist_freq = Array(Int32).new(30, 0)
      end

      def add_token(token : Token, & : ->) : Nil
        @tokens << token
        if @tokens.size >= MAX_BLOCK_TOKENS
          write_block(final: false)
          yield
        end
      end

      def write_block(final : Bool = false) : Nil
        return if @tokens.empty? && !final

        if @tokens.empty? && final
          # Write empty final block (stored)
          @writer.write_bit(true)   # BFINAL
          @writer.write_bits(0_u32, 2) # BTYPE = stored
          @writer.align_to_byte
          @writer.write_bits(0_u32, 16) # LEN = 0
          @writer.write_bits(0xFFFF_u32, 16) # NLEN
          return
        end

        # Compute frequency tables and extra bits in a single pass (reuse arrays)
        lit_freq = @lit_freq
        dist_freq = @dist_freq
        lit_freq.fill(0)
        dist_freq.fill(0)
        extra_bits_total = 0
        has_matches = false

        @tokens.each do |token|
          if token.literal?
            lit_freq[token.literal.not_nil!.to_i32] += 1
          else
            has_matches = true
            lit_code = length_to_code(token.length)
            lit_freq[lit_code] += 1
            dist_code = distance_to_code(token.distance)
            dist_freq[dist_code] += 1
            extra_bits_total += Huffman::LENGTH_EXTRA[lit_code - 257]
            extra_bits_total += Huffman::DISTANCE_EXTRA[dist_code]
          end
        end
        lit_freq[END_OF_BLOCK.to_i32] += 1  # End of block

        # Build encoders
        lit_encoder = Huffman::Encoder.new(lit_freq, max_bits: 15)
        dist_encoder = Huffman::Encoder.new(dist_freq, max_bits: 15)

        # Decide between fixed and dynamic Huffman
        dynamic_size = estimate_dynamic_size(lit_encoder, dist_encoder, lit_freq, dist_freq, extra_bits_total)
        fixed_size = estimate_fixed_size(lit_freq, dist_freq, extra_bits_total)
        stored_size = estimate_stored_size
        if @level == NO_COMPRESSION || (!has_matches && stored_size <= dynamic_size && stored_size <= fixed_size)
          write_stored_block(final)
        elsif fixed_size <= dynamic_size
          write_fixed_block(final, lit_freq, dist_freq)
        else
          write_dynamic_block(final, lit_encoder, dist_encoder, lit_freq, dist_freq)
        end

        @tokens.clear
      end

      def flush_sync : Nil
        write_block(final: false)
        # Sync flush: write an empty stored block
        @writer.write_bit(false)
        @writer.write_bits(0_u32, 2)
        @writer.align_to_byte
        @writer.write_bits(0_u32, 16)
        @writer.write_bits(0xFFFF_u32, 16)
      end

      private def write_stored_block(final : Bool) : Nil
        # Collect all literals
        data = Bytes.new(@tokens.sum { |t| t.literal? ? 1 : t.length })
        pos = 0
        @tokens.each do |token|
          if token.literal?
            data[pos] = token.literal.not_nil!
            pos += 1
          end
          # For stored blocks we can't encode length/distance pairs,
          # so we should only use this for level 0
        end

        # Write in chunks of 65535 bytes
        offset = 0
        while offset < data.size
          chunk_size = {data.size - offset, 65535}.min
          is_last = final && (offset + chunk_size >= data.size)

          @writer.write_bit(is_last)
          @writer.write_bits(0_u32, 2)
          @writer.align_to_byte
          @writer.write_bits(chunk_size.to_u32, 16)
          @writer.write_bits((chunk_size ^ 0xFFFF).to_u32, 16)
          @writer.write_bytes(data[offset, chunk_size])
          offset += chunk_size
        end

        if data.empty? && final
          @writer.write_bit(true)
          @writer.write_bits(0_u32, 2)
          @writer.align_to_byte
          @writer.write_bits(0_u32, 16)
          @writer.write_bits(0xFFFF_u32, 16)
        end
      end

      private def write_fixed_block(final : Bool, lit_freq : Array(Int32), dist_freq : Array(Int32)) : Nil
        @writer.write_bit(final)
        @writer.write_bits(1_u32, 2)  # BTYPE = fixed

        # Use fixed Huffman codes
        fixed_lit = Huffman::Encoder.new(lit_freq.size.times.map { |i| lit_freq[i] > 0 ? 1 : 0 }.to_a, max_bits: 15)

        # Actually, for fixed Huffman we need to use the predefined code tables
        # Build encoder from fixed code lengths
        write_tokens_fixed
        write_eob_fixed
      end

      private def write_dynamic_block(final : Bool, lit_encoder : Huffman::Encoder, dist_encoder : Huffman::Encoder, lit_freq : Array(Int32), dist_freq : Array(Int32)) : Nil
        @writer.write_bit(final)
        @writer.write_bits(2_u32, 2)  # BTYPE = dynamic

        # Determine HLIT and HDIST
        hlit = 257
        (285).downto(257) do |i|
          if i < lit_encoder.lengths.size && lit_encoder.lengths[i] > 0
            hlit = i + 1
            break
          end
        end
        hlit = {hlit, 257}.max

        hdist = 1
        (29).downto(0) do |i|
          if i < dist_encoder.lengths.size && dist_encoder.lengths[i] > 0
            hdist = i + 1
            break
          end
        end
        hdist = {hdist, 1}.max

        # Build combined code lengths array
        all_lengths = Array(UInt8).new(hlit + hdist, 0_u8)
        hlit.times { |i| all_lengths[i] = i < lit_encoder.lengths.size ? lit_encoder.lengths[i] : 0_u8 }
        hdist.times { |i| all_lengths[hlit + i] = i < dist_encoder.lengths.size ? dist_encoder.lengths[i] : 0_u8 }

        # RLE encode the code lengths
        rle = rle_encode_lengths(all_lengths)

        # Build code-length alphabet frequencies
        cl_freq = Array(Int32).new(19, 0)
        rle.each { |sym, _, _| cl_freq[sym] += 1 }

        cl_encoder = Huffman::Encoder.new(cl_freq, max_bits: 7)

        # Determine HCLEN
        hclen = 4
        (18).downto(0) do |i|
          idx = Huffman::CODE_LENGTH_ORDER[i]
          if idx < cl_encoder.lengths.size && cl_encoder.lengths[idx] > 0
            hclen = i + 1
            break
          end
        end
        hclen = {hclen, 4}.max

        # Write header
        @writer.write_bits((hlit - 257).to_u32, 5)
        @writer.write_bits((hdist - 1).to_u32, 5)
        @writer.write_bits((hclen - 4).to_u32, 4)

        # Write code length code lengths in the special order
        hclen.times do |i|
          idx = Huffman::CODE_LENGTH_ORDER[i]
          len = idx < cl_encoder.lengths.size ? cl_encoder.lengths[idx] : 0_u8
          @writer.write_bits(len.to_u32, 3)
        end

        # Write RLE-encoded code lengths
        rle.each do |sym, extra_val, extra_bits|
          cl_encoder.encode(@writer, sym)
          @writer.write_bits(extra_val.to_u32, extra_bits) if extra_bits > 0
        end

        # Write tokens
        write_tokens(lit_encoder, dist_encoder)

        # Write end of block
        lit_encoder.encode(@writer, END_OF_BLOCK.to_i32)
      end

      private def write_tokens(lit_encoder : Huffman::Encoder, dist_encoder : Huffman::Encoder) : Nil
        @tokens.each do |token|
          if token.literal?
            lit_encoder.encode(@writer, token.literal.not_nil!.to_i32)
          else
            lit_code = length_to_code(token.length)
            lit_encoder.encode(@writer, lit_code)
            extra_bits = Huffman::LENGTH_EXTRA[lit_code - 257]
            if extra_bits > 0
              extra_val = token.length - Huffman::LENGTH_BASE[lit_code - 257]
              @writer.write_bits(extra_val.to_u32, extra_bits)
            end

            dist_code = distance_to_code(token.distance)
            dist_encoder.encode(@writer, dist_code)
            extra_bits = Huffman::DISTANCE_EXTRA[dist_code]
            if extra_bits > 0
              extra_val = token.distance - Huffman::DISTANCE_BASE[dist_code]
              @writer.write_bits(extra_val.to_u32, extra_bits)
            end
          end
        end
      end

      private def write_tokens_fixed : Nil
        @tokens.each do |token|
          if token.literal?
            write_fixed_literal(token.literal.not_nil!.to_i32)
          else
            lit_code = length_to_code(token.length)
            write_fixed_literal(lit_code)
            extra_bits = Huffman::LENGTH_EXTRA[lit_code - 257]
            if extra_bits > 0
              extra_val = token.length - Huffman::LENGTH_BASE[lit_code - 257]
              @writer.write_bits(extra_val.to_u32, extra_bits)
            end

            dist_code = distance_to_code(token.distance)
            write_fixed_distance(dist_code)
            extra_bits = Huffman::DISTANCE_EXTRA[dist_code]
            if extra_bits > 0
              extra_val = token.distance - Huffman::DISTANCE_BASE[dist_code]
              @writer.write_bits(extra_val.to_u32, extra_bits)
            end
          end
        end
      end

      private def write_eob_fixed : Nil
        write_fixed_literal(END_OF_BLOCK.to_i32)
      end

      private def write_fixed_literal(symbol : Int32) : Nil
        # Fixed Huffman codes (RFC 1951 section 3.2.6)
        if symbol <= 143
          # 8-bit codes: 00110000 (48) to 10111111 (191)
          code = symbol + 0x30
          @writer.write_bits_reversed(code.to_u32, 8)
        elsif symbol <= 255
          # 9-bit codes: 110010000 (400) to 111111111 (511)
          code = symbol - 144 + 0x190
          @writer.write_bits_reversed(code.to_u32, 9)
        elsif symbol <= 279
          # 7-bit codes: 0000000 (0) to 0010111 (23)
          code = symbol - 256
          @writer.write_bits_reversed(code.to_u32, 7)
        else
          # 8-bit codes: 11000000 (192) to 11000111 (199)
          code = symbol - 280 + 0xC0
          @writer.write_bits_reversed(code.to_u32, 8)
        end
      end

      private def write_fixed_distance(code : Int32) : Nil
        # All distance codes are 5 bits
        @writer.write_bits_reversed(code.to_u32, 5)
      end

      private def rle_encode_lengths(lengths : Array(UInt8)) : Array({Int32, Int32, Int32})
        result = [] of {Int32, Int32, Int32}  # {symbol, extra_value, extra_bits}
        i = 0
        while i < lengths.size
          len = lengths[i]
          run = 1
          while i + run < lengths.size && lengths[i + run] == len && run < 138
            run += 1
          end

          if len == 0
            remaining = run
            while remaining > 0
              if remaining >= 11
                repeat = {remaining, 138}.min
                result << {18, repeat - 11, 7}
                remaining -= repeat
              elsif remaining >= 3
                repeat = {remaining, 10}.min
                result << {17, repeat - 3, 3}
                remaining -= repeat
              else
                result << {0, 0, 0}
                remaining -= 1
              end
            end
          else
            result << {len.to_i32, 0, 0}
            remaining = run - 1
            while remaining > 0
              if remaining >= 3
                repeat = {remaining, 6}.min
                result << {16, repeat - 3, 2}
                remaining -= repeat
              else
                result << {len.to_i32, 0, 0}
                remaining -= 1
              end
            end
          end
          i += run
        end
        result
      end

      private def estimate_dynamic_size(lit_enc : Huffman::Encoder, dist_enc : Huffman::Encoder, lit_freq : Array(Int32), dist_freq : Array(Int32), extra_bits_total : Int32) : Int32
        bits = 3 + 5 + 5 + 4  # Block header + HLIT + HDIST + HCLEN
        bits += 19 * 3  # Max code length code lengths
        bits += 100  # Rough estimate for RLE-encoded code lengths
        lit_freq.each_with_index do |f, i|
          bits += f * lit_enc.lengths[i].to_i32 if f > 0 && i < lit_enc.lengths.size
        end
        dist_freq.each_with_index do |f, i|
          bits += f * dist_enc.lengths[i].to_i32 if f > 0 && i < dist_enc.lengths.size
        end
        bits + extra_bits_total
      end

      private def estimate_fixed_size(lit_freq : Array(Int32), dist_freq : Array(Int32), extra_bits_total : Int32) : Int32
        bits = 3  # Block header
        lit_freq.each_with_index do |f, i|
          next if f == 0
          len = if i <= 143
                  8
                elsif i <= 255
                  9
                elsif i <= 279
                  7
                else
                  8
                end
          bits += f * len
        end
        dist_freq.each_with_index do |f, _|
          bits += f * 5
        end
        bits + extra_bits_total
      end

      private def estimate_stored_size : Int32
        byte_count = @tokens.sum { |t| t.literal? ? 1 : t.length }
        blocks = (byte_count / 65535.0).ceil.to_i32
        blocks = 1 if blocks == 0
        3 + blocks * (5 * 8) + byte_count * 8
      end

      private def length_to_code(length : Int32) : Int32
        Huffman::LENGTH_TO_CODE[length - 3].to_i32
      end

      # Lookup table for distance -> distance code (distances 1-512 direct, >512 uses shift)
      DIST_CODE_SMALL = begin
        table = StaticArray(UInt8, 512).new(0_u8)
        512.times do |i|
          dist = i + 1
          if dist <= 4
            table[i] = (dist - 1).to_u8
          else
            d = dist - 1
            n = 0
            v = d >> 1
            while v > 0
              n += 1
              v >>= 1
            end
            table[i] = (2 * n + ((d >> (n - 1)) & 1)).to_u8
          end
        end
        table
      end

      @[AlwaysInline]
      private def distance_to_code(distance : Int32) : Int32
        if distance <= 512
          DIST_CODE_SMALL[distance - 1].to_i32
        else
          # For large distances, shift down and use the table for the high bits
          d = distance - 1
          n = 0
          v = d >> 1
          while v > 0
            n += 1
            v >>= 1
          end
          2 * n + ((d >> (n - 1)) & 1)
        end
      end
    end
  end
end
