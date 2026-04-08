module Z
  module Huffman
    # Two-level lookup table for fast Huffman decoding.
    # Primary table: 11-bit index for literal/length trees, with secondary
    # tables for longer codes. Uses Slice for cache-friendly, bounds-check-free access.
    class Tree
      PRIMARY_BITS = 11
      PRIMARY_SIZE = 1 << PRIMARY_BITS

      # Entry format (UInt32):
      #   For direct entries: bits[15:0] = symbol, bits[19:16] = code length
      #   For redirect entries: bits[15:0] = secondary table offset, bits[19:16] = extra bits, bit 31 = 1
      REDIRECT_FLAG = 1_u32 << 31

      @table : Slice(UInt32)

      def initialize(code_lengths : Indexable(UInt8), max_symbol : Int32 = code_lengths.size)
        @table = build_table(code_lengths, max_symbol)
      end

      @[AlwaysInline]
      def decode(reader : BitReader) : UInt16
        tbl = @table.to_unsafe
        # Peek PRIMARY_BITS bits
        index = reader.peek_bits(PRIMARY_BITS)
        entry = tbl[index]

        if entry & REDIRECT_FLAG == 0
          # Direct entry
          len = (entry >> 16) & 0xF
          reader.drop_bits(len.to_i32)
          (entry & 0xFFFF).to_u16
        else
          # Secondary table lookup
          extra_bits = ((entry >> 16) & 0xF).to_i32
          offset = (entry & 0xFFFF).to_i32
          reader.drop_bits(PRIMARY_BITS)
          index2 = reader.peek_bits(extra_bits)
          entry2 = tbl[PRIMARY_SIZE + offset + index2]
          len2 = (entry2 >> 16) & 0xF
          reader.drop_bits(len2.to_i32)
          (entry2 & 0xFFFF).to_u16
        end
      end

      private def build_table(code_lengths : Indexable(UInt8), max_symbol : Int32) : Slice(UInt32)
        max_len = 0
        code_lengths.each_with_index do |len, i|
          break if i >= max_symbol
          max_len = len.to_i if len > max_len
        end

        return Slice(UInt32).new(PRIMARY_SIZE, 0_u32) if max_len == 0

        # Count codes of each length
        bl_count = Array(Int32).new(max_len + 1, 0)
        max_symbol.times do |i|
          bl_count[code_lengths[i]] += 1 if code_lengths[i] > 0
        end

        # Compute next_code for each length (canonical Huffman)
        next_code = Array(UInt32).new(max_len + 1, 0_u32)
        code = 0_u32
        bl_count[0] = 0
        (1..max_len).each do |bits|
          code = (code + bl_count[bits - 1]) << 1
          next_code[bits] = code
        end

        # Assign codes to symbols
        codes = Array(UInt32).new(max_symbol, 0_u32)
        lengths = Array(UInt8).new(max_symbol, 0_u8)
        max_symbol.times do |i|
          len = code_lengths[i]
          if len > 0
            codes[i] = next_code[len]
            lengths[i] = len
            next_code[len] += 1
          end
        end

        # Build tables
        secondary_needed = 0
        if max_len > PRIMARY_BITS
          secondary_needed = calculate_secondary_space(codes, lengths, max_symbol, max_len)
        end

        table = Slice(UInt32).new(PRIMARY_SIZE + secondary_needed, 0_u32)

        # Fill primary table entries for codes <= PRIMARY_BITS
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len == 0 || len > PRIMARY_BITS

          code_val = reverse_bits(codes[i], len)
          # Fill all entries where the extra bits can vary
          step = 1 << len
          j = code_val.to_i
          while j < PRIMARY_SIZE
            table[j] = i.to_u32 | (len.to_u32 << 16)
            j += step
          end
        end

        # Fill secondary tables for codes > PRIMARY_BITS
        if max_len > PRIMARY_BITS
          fill_secondary_tables(table, codes, lengths, max_symbol, max_len)
        end

        table
      end

      private def calculate_secondary_space(codes : Array(UInt32), lengths : Array(UInt8), max_symbol : Int32, max_len : Int32) : Int32
        prefix_max_extra = Array(Int32).new(PRIMARY_SIZE, 0)
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0
          prefix = reverse_bits(codes[i], len) & (PRIMARY_SIZE - 1)
          extra = len - PRIMARY_BITS
          prefix_max_extra[prefix] = extra if extra > prefix_max_extra[prefix]
        end

        total = 0
        PRIMARY_SIZE.times do |p|
          total += (1 << prefix_max_extra[p]) if prefix_max_extra[p] > 0
        end
        total
      end

      private def fill_secondary_tables(table : Slice(UInt32), codes : Array(UInt32), lengths : Array(UInt8), max_symbol : Int32, max_len : Int32) : Nil
        # Pass 1: find max extra bits per primary prefix
        prefix_max_extra = Array(Int32).new(PRIMARY_SIZE, 0)
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0
          prefix = reverse_bits(codes[i], len) & (PRIMARY_SIZE - 1)
          extra = len - PRIMARY_BITS
          prefix_max_extra[prefix] = extra if extra > prefix_max_extra[prefix]
        end

        # Pass 2: assign offsets and set redirect entries
        prefix_offsets = Array(Int32).new(PRIMARY_SIZE, 0)
        secondary_offset = 0
        PRIMARY_SIZE.times do |p|
          max_extra = prefix_max_extra[p]
          next if max_extra == 0
          prefix_offsets[p] = secondary_offset
          table[p] = REDIRECT_FLAG | (max_extra.to_u32 << 16) | secondary_offset.to_u32
          secondary_offset += (1 << max_extra)
        end

        # Pass 3: fill secondary table entries
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0

          reversed = reverse_bits(codes[i], len)
          prefix = reversed & (PRIMARY_SIZE - 1)
          offset = prefix_offsets[prefix]
          max_extra = prefix_max_extra[prefix]

          secondary_bits = reversed >> PRIMARY_BITS
          extra = len - PRIMARY_BITS
          step = 1 << extra
          j = secondary_bits.to_i
          while j < (1 << max_extra)
            table[PRIMARY_SIZE + offset + j] = i.to_u32 | (extra.to_u32 << 16)
            j += step
          end
        end
      end

      private def reverse_bits(code : UInt32, length : Int32) : UInt32
        Huffman.reverse_bits(code, length)
      end
    end
  end
end
