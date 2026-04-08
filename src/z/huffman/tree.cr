module Z
  module Huffman
    # Two-level lookup table for fast Huffman decoding.
    # Primary table: 9-bit index. Each entry is either a resolved symbol
    # or a pointer to a secondary table for longer codes.
    class Tree
      PRIMARY_BITS = 9
      PRIMARY_SIZE = 1 << PRIMARY_BITS

      # Entry format (UInt32):
      #   For direct entries: bits[15:0] = symbol, bits[19:16] = code length
      #   For redirect entries: bits[15:0] = secondary table offset, bits[19:16] = extra bits, bit 31 = 1
      REDIRECT_FLAG = 1_u32 << 31

      @table : Array(UInt32)

      def initialize(code_lengths : Indexable(UInt8), max_symbol : Int32 = code_lengths.size)
        @table = build_table(code_lengths, max_symbol)
      end

      def decode(reader : BitReader) : UInt16
        # Peek PRIMARY_BITS bits
        index = reader.peek_bits(PRIMARY_BITS)
        entry = @table[index]

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
          entry2 = @table[PRIMARY_SIZE + offset + index2]
          len2 = (entry2 >> 16) & 0xF
          reader.drop_bits(len2.to_i32)
          (entry2 & 0xFFFF).to_u16
        end
      end

      private def build_table(code_lengths : Indexable(UInt8), max_symbol : Int32) : Array(UInt32)
        max_len = 0
        code_lengths.each_with_index do |len, i|
          break if i >= max_symbol
          max_len = len.to_i if len > max_len
        end

        return Array(UInt32).new(PRIMARY_SIZE, 0_u32) if max_len == 0

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
          # Calculate secondary table space needed
          max_symbol.times do |i|
            if lengths[i] > PRIMARY_BITS
              # This code needs a secondary table entry
              secondary_needed += 0 # We'll calculate below
            end
          end
          # Group by primary prefix to determine secondary table sizes
          secondary_needed = calculate_secondary_space(codes, lengths, max_symbol, max_len)
        end

        table = Array(UInt32).new(PRIMARY_SIZE + secondary_needed, 0_u32)

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
        # Group codes by their PRIMARY_BITS prefix
        prefixes = Hash(UInt32, Int32).new(0)
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0
          prefix = reverse_bits(codes[i], len) & (PRIMARY_SIZE - 1)
          extra = len - PRIMARY_BITS
          size = 1 << extra
          current = prefixes[prefix]?
          prefixes[prefix] = {current || 0, size}.max
        end

        # For each unique prefix, we need a secondary table of size 2^(max_extra_for_prefix)
        # But we need to find the max extra bits for each prefix group
        prefix_max_extra = Hash(UInt32, Int32).new(0)
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0
          prefix = reverse_bits(codes[i], len) & (PRIMARY_SIZE - 1)
          extra = len - PRIMARY_BITS
          current = prefix_max_extra[prefix]? || 0
          prefix_max_extra[prefix] = extra if extra > current
        end

        total = 0
        prefix_max_extra.each_value { |extra| total += (1 << extra) }
        total
      end

      private def fill_secondary_tables(table : Array(UInt32), codes : Array(UInt32), lengths : Array(UInt8), max_symbol : Int32, max_len : Int32) : Nil
        # Find unique prefixes and their max extra bits
        prefix_max_extra = Hash(UInt32, Int32).new(0)
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0
          prefix = reverse_bits(codes[i], len) & (PRIMARY_SIZE - 1)
          extra = len - PRIMARY_BITS
          current = prefix_max_extra[prefix]? || 0
          prefix_max_extra[prefix] = extra if extra > current
        end

        # Allocate secondary tables
        secondary_offset = 0
        prefix_offsets = Hash(UInt32, {Int32, Int32}).new  # prefix -> {offset, max_extra}

        prefix_max_extra.each do |prefix, max_extra|
          prefix_offsets[prefix] = {secondary_offset, max_extra}
          # Set redirect entry in primary table
          table[prefix] = REDIRECT_FLAG | (max_extra.to_u32 << 16) | secondary_offset.to_u32
          secondary_offset += (1 << max_extra)
        end

        # Fill secondary table entries
        max_symbol.times do |i|
          len = lengths[i].to_i
          next if len <= PRIMARY_BITS || len == 0

          reversed = reverse_bits(codes[i], len)
          prefix = reversed & (PRIMARY_SIZE - 1)
          offset_info = prefix_offsets[prefix]
          offset = offset_info[0]
          max_extra = offset_info[1]

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
