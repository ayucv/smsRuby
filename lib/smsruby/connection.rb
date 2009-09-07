require 'sms'
require 'smsruby/error'

#
# The Connection class represent the connection layer. Contains all values that
# describe an available connection that is associated with an attach phone.
# Implements methods for comunicating with the phone for send/receive messages
# and for obtain information about associated phone
#
class Connection

  include Sms

  # Reference the status of the current connection
  attr_accessor :status
  # Reference if the current connection it's allow to send, receive or both
  attr_accessor :typec
  # Reference the associated port for the current connection
  attr_reader :port
  # Represent the unique id of the current connection
  attr_reader :id_connection
  # Reference model of the phone attached to the current connection
  attr_reader :phone_model
  # Reference manufacter of the phone attached to the current connection
  attr_reader :phone_manufacter
  # Reference the installed software revition in the phone attached to the current connection
  attr_reader :phone_revsoft
  # Reference imei of the phone attached to the current connection
  attr_reader :phone_imei


  #
  # Initialize the connection reprensented by name through businit function provided
  # by the sms shared object. In the same way initialize all class attributes.
  #
  def initialize(name,port)
    begin
      if RUBY_PLATFORM =~ /(win|w)32$/
       path = ENV['userprofile']+'/_gnokiirc'
      elsif RUBY_PLATFORM =~ /linux/
       path = ENV['HOME']+'/.gnokiirc'
      end
      error=businit(name, path)
      error <= 0  ? (error==-500 ? (raise "The maximum number of connection has been open") : @id_connection=error.to_i*-1) : exception(error)
      @port = port
      @phone_model=phoneModel(@id_connection)
      @phone_manufacter=phoneManufacter(@id_connection)
      @phone_revsoft=phoneRevSoft(@id_connection)
      @phone_imei=(phoneImei(@id_connection)).gsub(/[\s\D]/, "")
      @typec='none'
      @status='available'
    end
  end

  #
  # Allow to test and existing connection to verify if is still available. Return
  # 0 if is still available, diferent from 0 otherwise.
  #
  def test
    return testconn(@id_connection)
  end

  #
  # Return the signal level of the phone asociatted with the current connection
  #
  def signallevel
    return rf_level(@id_connection)
  end

  #
  # Return the battery level of the phone asociatted with the current connection
  #
  def batterylevel
    return bat_level(@id_connection)
  end

  #
  # Terminate the current connection
  #
  def close
    busterminate(@id_connection)
  end

  #
  # Execute a specific function from the shared object depending of type option value
  # specified in hsh. If an error occurs an exception will be thrown
  #
  def execute(hsh)
    cmd = hsh[:type]

    case cmd
    when /send/
      @status = 'sending'
      error = 0
      puts ":: Manufacter sending the message: "+@phone_manufacter.to_s+' in port: '+@port.to_s+' with id: '+@id_connection.to_s+"\n"
      error= send_sms(hsh[:dst], hsh[:msj], hsh[:smsc], hsh[:report], hsh[:validity], @id_connection)
      #puts ':: The return error in execute send function is: '+error.to_s+"\n"
      sleep(7)
    when /receive/
      @status = 'receiving'
      msj=[]
      nmsj=0
	puts "El id que le paso es: #{@id_connection}"
      error = get_sms(@id_connection)
      error <= 0 ? number=error.to_i*-1 : exception(error)
      number.times { |i|
          m = get_msj(i,@id_connection)
          if(m.type_sms.eql?("Inbox Message"))
            msj[nmsj] = m  if (m.error == 0)
            nmsj+=1 if m.error ==0
          end
        }
      return msj
    end
    exception(error) unless error==0
  end

  def type(status)
    case status
      when 0 then return "unread"
      when 1 then return "read"
      when 2 then return "sent"
      when 3 then return "unsent"
    end
  end

  #
  # Throws a diferent exception depending of specified error code
  #
  def exception (error)
    case error
      when 1..9 then raise ErrorHandler::GeneralError.new(error)
      when 10..15 then raise ErrorHandler::StatemachineError.new(error)
      when 16..18 then raise ErrorHandler::LocationError.new(error)
      when 19..21 then raise ErrorHandler::FormatError.new(error)
      when 22..25 then raise ErrorHandler::CallError.new(error)
      when 26..29 then raise ErrorHandler::OtherError.new(error)
      when 30..35 then raise ErrorHandler::ConfigError.new(error)
    end
  end

end
