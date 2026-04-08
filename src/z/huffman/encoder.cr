module Z
  module Huffman
    class Encoder
      getter codes : Array(UInt16)
      getter lengths : Array(UInt8)

      def initialize(frequencies : Array(Int32), max_bits : Int32 = 15)
        @codes = Array(UInt16).new(frequencies.size, 0_u16)
        @lengths = Array(UInt8).new(frequencies.size, 0_u8)
        build(frequencies, max_bits)
      end

      def encode(writer : BitWriter, symbol : Int32) : Nil
        writer.write_bits(@codes[symbol].to_u32, @lengths[symbol].to_i32)
      end

      private def build(frequencies : Array(Int32), max_bits : Int32) : Nil
        n = frequencies.size
        return if n == 0

        # Count non-zero frequencies
        non_zero = 0
        single_sym = -1
        frequencies.each_with_index do |f, i|
          if f > 0
            non_zero += 1
            single_sym = i
          end
        end

        return if non_zero == 0

        if non_zero == 1
          # Special case: single symbol gets code length 1
          @lengths[single_sym] = 1_u8
          @codes[single_sym] = 0_u16
          return
        end

        # Build code lengths using package-merge for length limiting,
        # or the simpler approach: build tree then limit
        bl = build_lengths(frequencies, max_bits)
        bl.each_with_index { |len, i| @lengths[i] = len }

        # Generate canonical codes from lengths
        generate_codes
      end

      private def build_lengths(frequencies : Array(Int32), max_bits : Int32) : Array(UInt8)
        n = frequencies.size
        lengths = Array(UInt8).new(n, 0_u8)

        # Build Huffman tree using a min-heap approach
        # Create list of (frequency, symbol) sorted
        symbols = [] of {Int64, Int32}
        frequencies.each_with_index do |f, i|
          symbols << {f.to_i64, i} if f > 0
        end
        symbols.sort_by! { |f, _| f }

        # Huffman tree building with two queues (optimal)
        leaves = symbols.dup
        internal = [] of {Int64, Int32}  # {frequency, node_index}

        # Build tree and record depths
        # Using a simplified approach: build tree, compute depths
        node_count = symbols.size * 2 - 1
        parent = Array(Int32).new(node_count, -1)
        node_freq = Array(Int64).new(node_count, 0_i64)

        # Initialize leaves
        leaf_idx = 0
        int_idx = 0
        next_node = symbols.size

        while (leaf_idx + int_idx) < (node_count - 1)
          # Pick two minimum nodes using two-queue merge
          f1, n1, leaf_idx, int_idx = pick_min_node(leaves, leaf_idx, internal, int_idx, symbols.size)
          f2, n2, leaf_idx, int_idx = pick_min_node(leaves, leaf_idx, internal, int_idx, symbols.size)

          parent[n1] = next_node
          parent[n2] = next_node
          combined_freq = f1 + f2
          internal << {combined_freq, next_node - symbols.size}
          next_node += 1
        end

        # Compute depths
        depths = Array(Int32).new(node_count, 0)
        # Root has no parent, traverse from root down
        # Actually, traverse from each leaf up to root
        symbols.each_with_index do |(_, sym), leaf_i|
          depth = 0
          node = leaf_i
          while parent[node] != -1
            depth += 1
            node = parent[node]
          end
          lengths[sym] = depth.to_u8
        end

        # Limit code lengths to max_bits
        limit_lengths(lengths, max_bits, frequencies)

        lengths
      end

      private def limit_lengths(lengths : Array(UInt8), max_bits : Int32, frequencies : Array(Int32)) : Nil
        max_found = lengths.max.to_i32
        return if max_found <= max_bits

        # Clamp overlong codes to max_bits
        lengths.each_with_index do |len, i|
          lengths[i] = max_bits.to_u8 if len > max_bits
        end

        # Fix Kraft inequality violation using integer arithmetic.
        # Kraft sum in fixed-point: each code of length L contributes 2^(max_bits - L).
        # Valid tree requires kraft_sum <= 2^max_bits.
        target = 1_i64 << max_bits

        loop do
          kraft_sum = 0_i64
          lengths.each { |len| kraft_sum += (1_i64 << (max_bits - len)) if len > 0 }
          break if kraft_sum <= target

          # Find the symbol with shortest code length and lengthen it
          min_len = max_bits
          min_idx = -1
          lengths.each_with_index do |len, i|
            if len > 0 && len < min_len
              min_len = len.to_i32
              min_idx = i
            end
          end
          break if min_idx == -1
          lengths[min_idx] = (lengths[min_idx] + 1).to_u8
        end
      end

      private def pick_min_node(leaves, leaf_idx, internal, int_idx, num_leaves) : {Int64, Int32, Int32, Int32}
        has_leaf = leaf_idx < leaves.size
        has_int = int_idx < internal.size

        use_leaf = if has_leaf && has_int
                     leaves[leaf_idx][0] <= internal[int_idx][0]
                   else
                     has_leaf
                   end

        if use_leaf
          {leaves[leaf_idx][0], leaf_idx, leaf_idx + 1, int_idx}
        else
          {internal[int_idx][0], num_leaves + int_idx, leaf_idx, int_idx + 1}
        end
      end

      private def generate_codes : Nil
        max_len = 0
        @lengths.each { |len| max_len = len.to_i32 if len > max_len }
        return if max_len == 0

        # Count codes of each length
        bl_count = Array(Int32).new(max_len + 1, 0)
        @lengths.each { |len| bl_count[len] += 1 if len > 0 }

        # Compute starting code for each length
        next_code = Array(UInt32).new(max_len + 1, 0_u32)
        code = 0_u32
        bl_count[0] = 0
        (1..max_len).each do |bits|
          code = (code + bl_count[bits - 1]) << 1
          next_code[bits] = code
        end

        # Assign codes (reversed for LSB-first output)
        @lengths.each_with_index do |len, i|
          if len > 0
            canonical = next_code[len]
            next_code[len] += 1
            @codes[i] = Huffman.reverse_bits(canonical, len.to_i32).to_u16
          end
        end
      end
    end
  end
end
