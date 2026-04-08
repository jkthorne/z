module Z
  VERSION = "0.1.0"
end

require "./z/error"
require "./z/checksums/adler32"
require "./z/checksums/crc32"
require "./z/bits/bit_reader"
require "./z/bits/bit_writer"
require "./z/huffman/tables"
require "./z/huffman/tree"
require "./z/deflate/deflate"
require "./z/deflate/inflate"
require "./z/deflate/reader"
