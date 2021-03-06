require 'smsruby/send'
require 'smsruby/receive'

#
# The Smsruby class represent the connection between the client and the SMS middleware.
# Defines the API functions of the SMS middleware
#
class Smsruby

  # Reference an instance of the Sender class
  attr_reader :sender
  # Reference an instance of the Receive class
  attr_reader :receiver

  #
  # Obtain the sender and receiver instances, allowing users to send and receive
  # messages trought the API functions.
  # The initialize function can receive 4 arguments: the first one is the send type
  # to be used by the Sender class, the second one is the location of the configuration
  # file used by the Sender class, the third one is the receivetype used in the Receive
  # class and the fourth one is the time that receive threads will remain active. If 0 is
  # past, receive threads will remain active until stop_receive method is called.
  #
  # A simple example of how to use smsRuby is shown below:
  #
  # require 'rubygems'
  # require 'smsruby'
  #
  # sms = Smsruby.new
  #
  # sms.sender.dst=['0412123456']
  # sms.send("Hello world")
  #
  # sms.receive{ |message,dest|
  #   puts "Hello world"
  # }
  #
  # Other example:
  #
  # require 'rubygems'
  # require 'smsruby'
  #
  # sms = Smsruby.new(:sendtype=> BDsend.new, :location=> 'config_sms.yml', :receivetype=> 0, :time=> 15, :ports=>['/dev/ttyACM0'])
  #
  # sms.send("Hello world")
  #
  # sms.receive(['358719846826017']){ |message,dest|
  #   puts "Message received: #{message.text}, from #{message.source_number}"
  #   puts "The phone receiving the message has imei number #{dest}"
  # }
  #
  # A final example:
  #
  # require 'rubygems'
  # require 'smsruby'
  #
  # sms = Smsruby.new
  #
  # sms.sender.sendtype = Configsend.new
  # sms.send("Hello world")
  #
  # sms.receiver.receivetype=1
  # sms.receive(['358719846826017']){ |message,dest|
  #   puts "Message received: #{message.text}, from #{message.source_number}"
  #   puts "The phone receiving the message has imei number #{dest}"
  # }
  #
  def initialize(*args)
    begin
      params={}
      params=args.pop if args.last.is_a? Hash
      !params[:sendtype] ? sendtype=Plainsend.new : sendtype = params[:sendtype]
      !params[:location] ? location = 'config_sms.yml' : location = params[:location]
      !params[:receivetyoe] ? receivetype = 0 : receivetype = params[:receivetype]
      !params[:time] ? time = 0 : time = params[:time]
      !params[:ports] ? ports=nil : ports = params[:ports]
      @sender=Sender.new(sendtype,location)
      @receiver=Receive.new(receivetype,time)
      @sender.adm.open_ports(ports) unless @sender.adm.avlconn
     rescue Exception => e
        puts "Instance of connection administrator fail. Detail: #{e.message}"
    end
  end

  #
  # High level function to send an SMS message. The text to be sent must be passed
  # as an argument. the values of the other options can be set trought the Sender
  # class, the destination number(s) is required. A code block can be past to send
  # function and will be executed if an error occurs sending the message. The code
  # block can use one argument, this is the string error giving by Sender class
  #
  def send(msj)
    @sender.send(msj){|e| yield e if block_given?}
  end

  #
  # Hight level function to receive SMS message(s). The imei of the phones that are
  # going to receive can be passed as an argument, if not, all the phones configured 
  # to receive ( trought config_sms.yml ) will be used. The values of the other options
  # can be set trought the Receive class. A code block can be passed to the receive
  # function and will be executed for every received message, the block can use 2
  # given arguments. The first argument is a message object with the following structure:
  #
  # message{
  #   int error               if error is different from 0 an error has ocurred
	#   int index               the index memory in the phone of the received message
	#   string date             reception date of the message
	#   string status           the status of the received message (read, unread ,unknown,..)
	#   string source_number    The number of the phone sending the message
	#   string text             The text of the received message
	#   string type_sms         The sms type of the received message (text, mms,...)
  # }
  #
  # The second argument represent the imei of the phone receiving the message
  #
  def receive(imeis=nil)
    @receiver.receive(imeis){|x,y| yield x,y if block_given? }
  end

  #
  # High level function to update and reload changes made to the configuration
  # file used in the Sender and the Connection Administrator
  #
  def update_config
    unless !@sender.adm.avlconn
      @sender.adm.reload_file
    end
  end

  #
  # High level function to update available connections in case a new one is
  # attached or an available one is unattach. An update of the configuration
  # file is also made when update_conn function is invoked
  #
  def update_conn
    if !@sender.adm.avlconn
      @sender.adm.open_profiles
    end
    @sender.adm.update_connections unless !@sender.adm.avlconn
    update_config
  end

  #
  # High level function to get all available connection. The result is a hash
  # containing the number of the connection and an object of the Connection class.
  # A code block can be passed to get_conn function and will be executed for each
  # available connection found by the Connection Administrator
  #
  def get_conn
    unless !@sender.adm.avlconn
      conn= @sender.adm.get_connections{ |pm|
        yield pm if block_given?
      }
    end
    return conn
  end

  #
  # High level function that wait for both receive and send threads and terminate
  # all active connections. A call to close function must be made at the end
  # of the user program
  #
  def close
    sleep(1)
    unless !@receiver.adm.avlconn
      Thread.list.each{|t| t.join if (t[:type]=='r' or t[:type]=='sp') }
      @receiver.adm.get_connections.each{|conn|
        conn[1].close
      }
    end
  end

  #
  # High level function that stops all receiving threads that are configured to
  # obtain messages for a spicified period of time
  #
  def stop_receive
   sleep(1)
   unless !@receiver.adm.avlconn
     Thread.list.each{|t| t.exit if t[:type]=='r'}
     @receiver.adm.get_connections.each{|conn|
       conn[1].status="available" if ((conn[1].typec=='r' and conn[1].status=="receiving") or (conn[1].typec=='sr' and conn[1].status=="receiving"))}
   end
  end

  #
  # High level function that wait for all active receive threads without terminate
  # the active connections.
  #
  def wait_receive
   sleep(1)
   unless !@receiver.adm.avlconn
     Thread.list.each{|t| t.join if t[:type]=='r'}
     @receiver.adm.get_connections.each{|conn|
       conn[1].status="available" if ((conn[1].typec=='r' and conn[1].status=="receiving") or (conn[1].typec=='sr' and conn[1].status=="receiving"))}
   end
  end

end
