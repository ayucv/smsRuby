require 'smsruby/adm_connection'
require 'rubygems'
require 'sqlite3'

#
# The Receive class represent the receive layer. Handles the reception of messages
# and the initialization of multiples threads to allow multiples connections to receive
# messages simultaniously
#
class Receive

  # Reference an instance for the Connection Administrator
  attr_reader :adm
  # Reference the list of messages
  attr_reader :list
  # Reference the type of receive that will be used (0: receive for a defined period of time, 1: receive messages ones )
  attr_accessor :receivetype
  # Represent the time in seconds that a particular connection will be receiving messages (for receivetype==0)
  attr_accessor :time


  #
  # Obtains and instance of the Connection Administrator to control all existing
  # connections. Due to the use of a singleton in the administrator, the same
  # created instance will be obtain, or will be created if an instance doesn't
  # exist. The type of receive and the period of time that will be used are passed
  # to initialize method. An Exception is thrown if the instance of Admconnection fail
  #
  def initialize(type,time)
      begin
        @receivetype=type
        @time =time
        @adm = AdmConnection.instance
      end
  end

  #
  # Represent the receive method of the Receive class. Will create the reception threads
  # acording with the imeis values passed as an argument. if imeis passed are nil will be 
  # created as many threads as connections configured to receive are found
  #
  def receive(imeis)
    begin
      if @adm.avlconn
        if imeis
          imeis.each do |i|
            if @adm.get_connections.inject(false){|res,act| (act[1].phone_imei==i.to_s and act[1].status=='available' and (act[1].typec=='r' or act[1].typec=='sr')) || res}
              t=Thread.new{receive_internal(i.to_s){|x,y| yield x,y if block_given? }}
              t[:type]='r'
            else
              @adm.log.warn "Can't receive message in connection with imei: #{i}." unless @adm.log.nil?
            end
          end
        else
          @adm.get_connections.select{ |n,act| (act.typec=='r' or act.typec=='sr') and act.status=='available'}.each do |i|
            t=Thread.new{receive_internal(i[1].phone_imei){|x,y| yield x,y if block_given? }}
            t[:type]='r'
          end
        end
      else
        raise "There are no active connections"
      end
    rescue Exception => e
      @adm.log.error "Error receiving messages #{e.message}. Detail: #{e.message}" unless @adm.log.nil?
      raise e
    end
  end

  #
  # Represent the method associated to the receive threads. Will handle the BD writting
  # of the received messages and will make the call of recieve method in the Connection
  # Administrator
  #
  def receive_internal(imei)
    begin
      db = SQLite3::Database.new('prueba.s3db')
      @adm.receive(to_hash(imei)){ |x,y|
        yield x,y if block_given?
        db.execute("INSERT INTO inbox (smsdate,phone_number,text) VALUES " + "('#{x.date}', '#{x.source_number}','#{x.text}');")
      }
    rescue Exception => e
      puts e.message
    end
  end

  #
  # Combine all option values into a hash to relate them
  #
  def to_hash(imei)
      { :type => 'receive',
        :imei => imei.gsub(/[\s\D]/, ""),
        :receivetype => self.receivetype,
        :time => self.time
        }
  end

end
