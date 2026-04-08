module Z
  module Deflate
    # LZ77 token: either a literal byte or a length/distance pair
    record Token, literal : UInt8? = nil, length : Int32 = 0, distance : Int32 = 0 do
      def literal? : Bool
        !literal.nil?
      end
    end

    # Compression level parameters
    record LevelConfig,
      max_chain : Int32,
      lazy : Bool,
      good_length : Int32,
      nice_length : Int32

    LEVEL_CONFIGS = [
      LevelConfig.new(0, false, 0, 0),         # 0: store only
      LevelConfig.new(4, false, 4, 8),          # 1
      LevelConfig.new(5, false, 5, 16),         # 2
      LevelConfig.new(6, false, 6, 32),         # 3
      LevelConfig.new(4, true, 4, 16),          # 4
      LevelConfig.new(8, true, 16, 32),         # 5
      LevelConfig.new(32, true, 32, 128),       # 6
      LevelConfig.new(64, true, 32, 128),       # 7
      LevelConfig.new(128, true, 128, 258),     # 8
      LevelConfig.new(4096, true, 258, 258),    # 9
    ]

    class LZ77
      HASH_SIZE = 1 << 15
      HASH_MASK = HASH_SIZE - 1

      @head : Array(UInt16)     # hash -> most recent position
      @prev : Array(UInt16)     # position -> previous position with same hash
      @window : Bytes           # sliding window
      @pos : Int32 = 0          # current position in window
      @lookahead : Int32 = 0    # bytes available ahead of pos
      @config : LevelConfig
      @hash : UInt32 = 0

      def initialize(level : Int32)
        @config = LEVEL_CONFIGS[level]
        @head = Array(UInt16).new(HASH_SIZE, 0_u16)
        @prev = Array(UInt16).new(WINDOW_SIZE, 0_u16)
        @window = Bytes.new(WINDOW_SIZE * 2)  # Double buffer for easy matching
      end

      def compress(input : Bytes, & : Token ->) : Nil
        return if input.empty?

        # Copy input into window buffer
        offset = 0
        while offset < input.size
          # Fill the lookahead buffer
          space = @window.size - (@pos + @lookahead)
          if space <= 0
            slide_window
            space = @window.size - (@pos + @lookahead)
          end

          copy = {input.size - offset, space}.min
          input[offset, copy].copy_to(@window[(@pos + @lookahead), copy])
          @lookahead += copy
          offset += copy

          # Process the lookahead
          process_lookahead { |token| yield token }
        end
      end

      def flush(& : Token ->) : Nil
        while @lookahead > 0
          process_one { |token| yield token }
        end
      end

      private def process_lookahead(& : Token ->) : Nil
        while @lookahead >= MIN_MATCH
          process_one { |token| yield token }
        end
      end

      private def process_one(& : Token ->) : Nil
        if @lookahead < MIN_MATCH
          yield Token.new(literal: @window[@pos])
          @pos += 1
          @lookahead -= 1
          return
        end

        update_hash(@pos)
        match_len, match_dist = find_best_match

        if @config.lazy && match_len >= MIN_MATCH && match_len < @config.nice_length
          # Try lazy matching: check if next position has a better match
          saved_len = match_len
          saved_dist = match_dist

          insert_hash(@pos)
          @pos += 1
          @lookahead -= 1

          if @lookahead >= MIN_MATCH
            update_hash(@pos)
            next_len, next_dist = find_best_match
            if next_len > saved_len
              # Better match at next position; emit the skipped byte as literal
              yield Token.new(literal: @window[@pos - 1])
              match_len = next_len
              match_dist = next_dist
            else
              # Original match was better; go back
              @pos -= 1
              @lookahead += 1
              match_len = saved_len
              match_dist = saved_dist
            end
          else
            # Not enough lookahead for next match
            yield Token.new(literal: @window[@pos - 1])
            return
          end
        end

        if match_len >= MIN_MATCH
          yield Token.new(length: match_len, distance: match_dist)
          # Insert hash entries for the match
          match_len.times do
            insert_hash(@pos) if @pos + MIN_MATCH <= @pos + @lookahead
            @pos += 1
            @lookahead -= 1
          end
        else
          yield Token.new(literal: @window[@pos])
          insert_hash(@pos)
          @pos += 1
          @lookahead -= 1
        end
      end

      private def find_best_match : {Int32, Int32}
        best_len = MIN_MATCH - 1
        best_dist = 0
        chain_len = @config.max_chain

        match_pos = @head[(@hash & HASH_MASK).to_i32]

        while chain_len > 0 && match_pos != 0
          # Calculate distance
          m = match_pos.to_i32
          dist = @pos - m
          break if dist <= 0 || dist > WINDOW_SIZE

          # Compare strings
          len = match_length(m, @pos, {MAX_MATCH, @lookahead}.min)

          if len > best_len
            best_len = len
            best_dist = dist
            break if len >= @config.nice_length || len >= @lookahead
          end

          match_pos = @prev[m & WINDOW_MASK]
          chain_len -= 1
        end

        {best_len, best_dist}
      end

      private def match_length(s1 : Int32, s2 : Int32, max_len : Int32) : Int32
        return 0 if max_len == 0
        p1 = @window.to_unsafe + s1
        p2 = @window.to_unsafe + s2
        len = 0

        # Compare 8 bytes at a time
        while len + 8 <= max_len
          v1 = (p1 + len).as(Pointer(UInt64)).value
          v2 = (p2 + len).as(Pointer(UInt64)).value
          xor = v1 ^ v2
          if xor != 0
            len += xor.trailing_zeros_count // 8
            return len > max_len ? max_len : len
          end
          len += 8
        end

        # Compare remaining bytes
        while len < max_len && p1[len] == p2[len]
          len += 1
        end
        len
      end

      private def update_hash(pos : Int32) : Nil
        if pos + 2 < @window.size
          @hash = ((@window[pos].to_u32 << 10) ^ (@window[pos + 1].to_u32 << 5) ^ @window[pos + 2].to_u32) & HASH_MASK
        end
      end

      private def insert_hash(pos : Int32) : Nil
        return if pos + 2 >= @window.size
        update_hash(pos)
        @prev[pos & WINDOW_MASK] = @head[@hash.to_i32]
        @head[@hash.to_i32] = pos.to_u16
      end

      private def slide_window : Nil
        # Shift window: move second half to first half
        @window[0, WINDOW_SIZE].copy_from(@window[WINDOW_SIZE, WINDOW_SIZE])

        # Update hash entries
        HASH_SIZE.times do |i|
          v = @head[i].to_i32
          @head[i] = v >= WINDOW_SIZE ? (v - WINDOW_SIZE).to_u16 : 0_u16
        end
        WINDOW_SIZE.times do |i|
          v = @prev[i].to_i32
          @prev[i] = v >= WINDOW_SIZE ? (v - WINDOW_SIZE).to_u16 : 0_u16
        end

        @pos -= WINDOW_SIZE
      end
    end
  end
end
