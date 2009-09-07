require 'sms'
module ErrorHandler

  #
  # The Error class represent the error layer. Inherit from standard error class
  # of ruby and allows to give a more specific description about produced errors
  #
  class Error < StandardError
    include Sms

    # Reference the id of the current error
    attr_reader :id
    # Reference a string message description of the current error
    attr_reader :message

    #
    # Initialize all attributes for error class receiving the id error. The
    # printError function of the shared object is used to obtain the string
    # message of the current error
    #
    def initialize(id)
      @id = id
      @message = printError(id)
    end
    
  end

  #
  # Represent the diferent classes for particular given errors. All the classes
  # inherits from Error class defined above.
  #
  class GeneralError < Error; end
  class ConfigError < Error; end
  class StatemachineError < Error; end
  class CallError < Error; end
  class OtherError < Error; end
  class FormatError < Error; end
  class LocationError < Error; end

end