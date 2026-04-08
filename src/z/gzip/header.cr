module Z
  module Gzip
    class Header
      property modification_time : Time = Time::UNIX_EPOCH
      property os : UInt8 = 255_u8
      property extra : Bytes? = nil
      property name : String? = nil
      property comment : String? = nil

      def initialize
      end
    end
  end
end
