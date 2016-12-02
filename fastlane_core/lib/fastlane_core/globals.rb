module FastlaneCore
  class Globals
    def self.captured_output
      unless @captured_output
        @captured_output = ""
      end
      @captured_output
    end
    def self.captured_output=(str)
      @captured_output=str
    end
    def self.capture_output?
      return @capture_output
    end
    
    def self.capture_output(flag)
      @capture_output = flag
    end
    
    def self.captured_output?
      if @captured_output.length > 0
        return true
      end
      return false
    end
    def self.verbose(flag)
        @verbose = flag
        # $verbose = flag  - after review add this as a backward shim, but it may interfer tests
    end
    def self.verbose?
      return @verbose
    end
  end
end