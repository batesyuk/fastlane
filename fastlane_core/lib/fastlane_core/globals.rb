module FastlaneCore
  class Globals
    def self.captured_output
      unless @captured_output
        @captured_output = ""
      end
      @captured_output
    end

    class << self
      attr_writer :captured_output
      attr_writer :capture_output
      attr_writer :verbose
    end

    def self.capture_output?
      return @capture_output
    end

    def self.captured_output?
      if @capture_output && @captured_output.length > 0
        return true
      end
      return false
    end

    def self.verbose?
      return @verbose
    end
  end
end
