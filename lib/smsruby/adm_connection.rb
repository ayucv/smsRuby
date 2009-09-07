require 'smsruby/connection'
require 'singleton'
require 'thread'
require 'logger'
require 'yaml'

#
# The AdmConnection class represent the SMS connection management layer for
# handling and controling connections (in case a pool of connections exist).
# It will also control the flow and the balance of the messages to be
# deliver through all active connections
#
class AdmConnection

  include Singleton

  # Represent a hash containing all connections availables to send or receive
  @@connections = {}
  # Reference all the consumer threads
  @@consu =[]
  # Reference a syncronization object to control access to critical resources
  attr_reader  :sync
  # Represent the number of items produced into de queue
  attr_reader :produced
  # Represent the number of items consumed of the total produced
  attr_reader :consumed
  # Represent a hash that groups all SMS delivery options
  attr_reader :options
  # Reference the log system to register the events
  attr_reader :log
  # Reference the config file for smsRuby
  attr_reader :config
  # Represent all the possible ports
  attr_reader :ports
  # Specify if there is iniialized connections or not
  attr_reader :avlconn


  #
  # Initialize the admin variables, the system log and the synchronization object
  #
  def initialize
    @sync=Synchronize.new
    @options={}
    @log=Logger.new('sms.log')
    @ports=[]
    @produced=0
    @consumed=0
    @avlconn=false
  end

  #
  # obtains all available connections an execute a code block for each connection
  # found if a code block is received
  #
  def get_connections
    @@connections.each{ |i,c| yield c if c.status!="disable"} if block_given?
    return @@connections
  end
  
  #
  # Set specific ports to checked. Try to open all specified connections and create.
  # Raise an exception if not functional connection is found. A call to open_profile
  # is made to open connections in the given ports
  #
  def open_ports(ports=nil)
    open=false
    #if RUBY_PLATFORM =~ /(win|w)32$/
      #9.times { |i| @ports.push("COM#{i}")}
    if RUBY_PLATFORM =~ /linux/  and ports.nil?
      9.times { |i|
        @ports.push("/dev/ttyUSB#{i}")
        @ports.push("/dev/ttyACM#{i}")
      }
    else
      if ports.nil?
        @log.error "No ports were specified"
        raise "No ports were specified"
      else
        ports.each{|p| @ports.push(p)}
      end
    end
    open = open_profiles
    @log.error "No active connections found or available connections fail" unless open
    raise 'No active connections found or available connections fail. See log for details' unless open
  end

  #
  # Used to open connections and load configuration file. Return true if at least
  # one connection could be open satisfactorily, false otherwise
  #
  def open_profiles
    begin
      open=false
      save_file(@ports)
      path = 'config_sms.yml'
      parse=YAML::parse(File.open(path))
      @config=parse.transform
      @ports.size.times do |i|
        open=open_conn("telf"+i.to_s,@ports[i]) || open
      end
      @avlconn=true if open
      open
    rescue Exception => e
      @log.error "Error openning connections. Detail #{e.message}"
    end
  end

  #
  # Check if a new connection had been attach.
  #
  def update_connections
    begin
      @@connections.each{ |i,c| t=c.test; c.status = "disable" if (t!=0 and t!=22 and t!=23)}
      @ports.select{ |i| (!@@connections.inject(false){|res,act| (act[1].port == i and act[1].status!="disable") || res }) }.each{|i|
        open_conn("telf"+@ports.index(i).to_s,i)
      }
    rescue Exception => e
      puts "An error has occurred updating connections. Exception:: #{e.message}\n"
      @log.error "An error has occurred updating connections. Exception:: #{e.message}" unless @log.nil?
    end
  end

  #
  # reload the configuration file to update changes
  #
  def reload_file
    parse=YAML::parse(File.open('config_sms.yml'))
    @config=parse.transform
  end

  #
  # Save the configuration file used for gnokii to load phone profiles and open
  # connections. The required information is specifyed in array
  #
  def save_file (array)
    begin
      i = 0
      if RUBY_PLATFORM =~ /(win|w)32$/
        path = ENV['userprofile']+'/_gnokiirc'
      elsif RUBY_PLATFORM =~ /linux/
        path = ENV['HOME']+'/.gnokiirc'
      end
      
      File.open(path, 'w') do |f2|
        array.each do |pos|
          f2.puts "[phone_telf" + i.to_s + "]"
          f2.puts "port = " + pos
          f2.puts "model = AT"
          f2.puts "connection = serial"
          i = i+1
        end
          f2.puts "[global]"
          f2.puts "port = COM3"
          f2.puts "model = AT"
          f2.puts "connection = serial"
          f2.puts '[logging]'
          f2.puts 'debug = off'
          f2.puts 'rlpdebug = off'
      end
    rescue SystemCallError
      @log.error "Problem writing the configuration file" unless @log.nil?
      raise "Problem writing the configuration file"
    end
  end

  #
  # Initialize a new connection with the specifyed name and port and add it to the
  # connections hash, wich holds all available connections. If an exception is
  # thrown an error will be register in the system log
  #
  def open_conn(name,port)
    begin
      open=true
      n = @@connections.size
      con = Connection.new(name,port)
      (@config['send']['imeis']).each { |item|con.typec = 's' if con.phone_imei.eql?(item.to_s)}
      (@config['receive']['imeis']).each {|item|
        (con.typec == 's' ? con.typec ='sr' : con.typec = 'r') if con.phone_imei.eql?(item.to_s)
      }
      con.typec = 's' if (con.typec!= 'r' and con.typec!='sr')
      puts ":: satisfactorily open a connection in port #{port} imei is #{con.phone_imei} and connection type is: #{con.typec} ::\n"
      @@connections.merge!({n => con})
    rescue ErrorHandler::Error => e
      #@log.info "Openning connection in #{port}..  #{e.message} Not Device Found " unless @log.nil?
      open=false
    rescue Exception => e
      @log.info "Openning connection in port #{port}.. #{e.message}" unless @log.nil?
      open=false
    end
    open
  end

  #
  # The internal send function for the Connection Administrator. The config value
  # specify the option values for the SMS messages to be send. It starts producer
  # and consumers to distribute the messages to the diferent available connections. A 
  # recovery send is started if at least one message fail to deliver in the first attempt.
  #
  def send(config)
    @options = config
    config[:dst].delete_if {|x| (!check_phone(x) and (@log.error "Incorrect phone number format for #{x}"if !check_phone(x)))} if !config[:dst].empty?
    if !config[:dst].empty?
      bool= !(@@connections.inject(true){|res,act| (act[1].status == "disable" or (act[1].typec=='r' or (act[1].typec=='sr' and act[1].status=="receiving"))) and res }) if !@@connections.empty?
      if !@@connections.empty? and bool
        @log.info "Starting send.. #{config[:dst].size} messages to be sent. " unless @log.nil?
        prod = Thread.new{producer(config[:dst])}
        conn=Thread.new{verify_connection(5)}
        pos=0
        @@connections.each do |i,c|
          unless c.typec=='r' or (c.typec=='sr' and c.status=="receiving") or c.status =="disable"
            @@consu[pos] = Thread.new{consumer(i,config[:dst].size)}
            pos+=1
          end
        end
        prod.join
        @@consu.each { |c|
          (c.stop? and c[:wfs]==1) ? (@@connections[c[:connid]].status="available"; c.exit) : c.join
        }
        @@consu.clear
        unless @sync.eq.empty?
          pos=0
          @@connections.each do |i,c|
            unless c.typec=='r' or (c.typec=='sr' and c.status=="receiving" ) or c.status =="disable"
              @@consu[pos]=Thread.new{send_emergency(i,config[:dst].size)}
              pos+=1
            end
          end
          @@consu.each { |c|
            (c.stop? and c[:wfs]==1) ? (@@connections[c[:connid]].status="available"; c.exit) : c.join
          }
          check=0
          while(!@sync.eq.empty?)
            check=1
            @log.error "Message: #{config[:msj][0,15]}... to #{@sync.eq.pop} couldn't be sent." unless @log.nil?
          end
          conn.exit
          error = "Message #{config[:msj][0,15]}... couldn't be sent to some destinations. See log for details." if !check
          yield error if block_given?
          raise error if check
        end
        conn.exit
      else
        warn = "Message: #{config[:msj][0,15]}... couldn't be sent. There are no active or available to send connections"
        @log.warn warn unless @log.nil?
        yield warn if block_given?
        raise warn
      end
    else
      warn = "Message: #{config[:msj][0,15]}... couldn't be sent. Bad format or no destination number were specified"
      @log.warn warn unless @log.nil?
      yield warn if block_given?
      raise warn
    end
  end

  #
  # Put all destination numbers (produce) into a shared buffer. A synchronization
  # with all active consumers is required to avoid data loss and incoherence. The
  # buffer has a limited size, so is up to the producer to handle this matter
  #
  def producer(dest)
    dest.each do |i|
      begin
        @sync.mutex.synchronize{
          @sync.full.wait(@sync.mutex) if (@sync.count == @sync.max)
          @sync.queue.push i.to_s
          #puts "Producer: #{i} produced"+"\n"
          @sync.mutexp.synchronize{
            @produced += 1 
          }
          @sync.empty.signal if @sync.count == 1
        }
      end
    end
  end

  #
  # Extract a destination number from the shared buffer and passed along with SMS
  # message option values to the excetute connection function. A synchronization
  # with the producer and all other consumers is required to avoid data loss and
  # incoherence
  #
  def consumer(n,max)
    Thread.current[:wfs]=0
    Thread.current[:type]='s'
    Thread.current[:connid]=n
    loop do
      @sync.mutexp.synchronize{
         (@@connections[n].status="available"; Thread.exit) if (@produced >= max && @sync.queue.empty?)
      }
      begin
        @sync.mutex.synchronize{
          while (@sync.count == 0)
            Thread.current[:wfs]=1
            @sync.empty.wait(@sync.mutex)
            Thread.current[:wfs]=0
          end
          Thread.current[:v] = @sync.queue.pop
          #puts ":: Consumer: in connection #{n} #{Thread.current[:v]} consumed \n"
          @sync.full.signal if (@sync.count == (@sync.max - 1))
        }
        retryable(:tries => 2, :on => ErrorHandler::Error) do
          @@connections[n].execute(to_hash(Thread.current[:v].to_s))
        end
        @consumed+=1
        @log.info "Message: #{@options[:msj][0,15]}... to #{Thread.current[:v].to_s} sent succsefull from connection with imei #{@@connections[n].phone_imei}." unless @log.nil?
      rescue ErrorHandler::Error => ex
        @log.error "Connection in port #{@@connections[n].port} fail sending message to #{Thread.current[:v]}, Message sent to emergency queue. Exception:: #{ex.message}" unless @log.nil?
        @sync.eq.push(Thread.current[:v])
      rescue Exception => ex
        @log.error "Connection in port #{@@connections[n].port} fail sending message to #{Thread.current[:v]}. Exception:: #{ex.message}" unless @log.nil?
      end
    end
  end

  #
  # Handles all unsend messages from the consumers due to diferent exceptions (no
  # signal in phone, error in sim card..). Try to send the messages recovering it
  # from an emergency queue and discarting it only if none of the active connections
  # is able to send the message.
  #
  def send_emergency(n,max)
    Thread.current[:wfs]=0
    Thread.current[:type]='s'
    Thread.current[:connid]=n
    loop do
      begin
        @sync.mutexe.synchronize{
          if (@sync.eq.size == 0 and @consumed < max)
            Thread.current[:wfs] =  1
            @sync.emptye.wait(@sync.mutexe)
            Thread.current[:wfs] = 0
          elsif (@consumed == max)
            @@connections[n].status="available";
            Thread.exit
          end
          unless @sync.eq.empty?
            Thread.current[:v]=@sync.eq.pop
            retryable(:tries => 2, :on => ErrorHandler::Error) do
              @@connections[n].execute(to_hash(Thread.current[:v].to_s))
            end
            @consumed+=1
            @log.info "EMessage: #{@options[:msj][0,15]}... to #{Thread.current[:v].to_s} sent succsefull from connection with imei #{@@connections[n].phone_imei}." unless @log.nil?
             p ':: Emergency message consumed '+(max-@consumed).to_s+' left'
            (Thread.list.each{|t| @sync.emptye.signal if (t!=Thread.current and t!=Thread.main and t[:wfs]==1)}) if @consumed == max
          end
        }
      rescue Exception => e
        @sync.mutexe.synchronize{
          @log.error "Connection in port #{@@connections[n].port} fail sending message to #{Thread.current[:v]} at emergency function. Exception:: #{e.message}" unless @log.nil?
          @sync.eq << Thread.current[:v]
          @sync.emptye.signal if @sync.eq.size==1
        }
        @@connections[n].status="available";
        Thread.exit
      end
    end
  end

  #
  # Check if a new connection had been attach while sending a message. This allows
  # to start new consumers dinamically and increase the performance
  #
  def verify_connection(seconds)
    begin
      n=0
      verify(0,seconds){
          @ports.select{ |i| (!@@connections.inject(false){|res,act| (act[1].port == i) || res }) }.each{|i|
            n=@@connections.size
            if open_conn("telf"+@ports.index(i).to_s,i)
              unless @@connections[n].typec=='r' or (@@connections[n].typec=='sr' and @@connections[n].status="receiving")
                @@consu[n]=Thread.new{consumer(n,@options[:dst].size)}
              end
            end
          }
      }
    rescue Exception => e
      puts "An error has occurred during execution of verify connection function. Exception:: #{e.message}"
      @log.error "An error has occurred during execution of verify connection function. Exception:: #{e.message}" unless @log.nil?
    end
  end

  #
  # Excecute every "seconds" for a period of "total" seconds a given code block.
  # If "total" is 0 the function will loop forever
  #
  def verify(total,seconds)
    start_total=Time.now
    loop do
      start_time = Time.now
      puts "Task started. #{start_time}"
      yield
      time_spent=Time.now - start_time
      puts "Task donde. #{Time.now}"+ "and spend #{time_spent}"
      break if ((Time.now - start_total) >= total and total != 0)
      sleep(seconds - time_spent) if time_spent < seconds
    end
  end
  
  #
  # The internal receive function for the Connection Administrator.
  #
  def receive(hash)
    begin
      conn=nil
      @@connections.each{|i,c|
         if c.phone_imei==hash[:imei]
          @log.info "Start receiving messages from connection with imei: #{hash[:imei]}." unless log.nil?
          conn=c
          break
         end
      }
      unless !conn
        if hash[:receivetype]==0
          verify(hash[:time],10){
            list = conn.execute(hash)
            unless !list
              list.each do |msj|
                @log.info "Message received in connection with imei #{conn.phone_imei} from #{msj.source_number}. #{msj.text}."
                yield msj,conn.phone_imei if block_given?
              end
            end
          }
        else
          list = conn.execute(hash)
          unless !list
            list.each do |msj|
              @log.info "Message received in connection with imei #{conn.phone_imei} from #{msj.source_number}. #{msj.text}."
              yield msj,conn.phone_imei if block_given?
            end
          end
        end
        conn.status='available'
      end
    rescue ErrorHandler::Error => e
      error = "Fail to receive more messages from connecion with imei #{hash[:imei]}. Detail: #{e.message}"
      @log.error error unless @log.nil?
      conn.status='available'
      raise error
    rescue Exception => e
      error = "Exception receiving messages from connecion with imei #{hash[:imei]}. Detail: #{e.message}"
      @log.error error unless @log.nil?
      conn.status='available'
      raise error
    end
  end

  #
  # Handles retry for a particular code block. The default numbers of retrys is set
  # to 1. The retry will be executed on any exception unless a type of error is
  # specified
  #
  def retryable(options = {}, &block)

    opts = { :tries => 1, :on => Exception }.merge(options)

    retry_exception, retries = opts[:on], opts[:tries]

    begin
      return yield
    rescue retry_exception
      retry if (retries -= 1) > 0
    end
    yield
  end

  #
  # Check the validity of the phone number format 
  #
  def check_phone(phone)
    phone_re = /^(\+\d{1,3}\d{3}\d{7})|(0\d{3})\d{7}$/
    m = phone_re.match(phone.to_s)
    m ? true : false
  end

  #
  # Combine all option values into a hash to relate them
  #
  def to_hash(num)
      { :type => 'send',
        :dst => num,
        :msj => self.options[:msj],
        :smsc =>self.options[:smsc],
        :report => self.options[:report],
        :validity => self.options[:validity]}
  end
end


#
# The Synchronize class contains all required variables to handle synchronization
# between producer - consumers and to protect critical resourses from concurrent
# access.
#
class Synchronize

  # Handle mutual exclution for queue
  attr_accessor :mutex
  # Handle mutual exclution for the produced variable (protect the variable)
  attr_accessor :mutexp
  # Handle mutual exclution for eq
  attr_accessor :mutexe
  # Represent the condition variable for handling an empty queue "queue"
  attr_accessor :empty
  # Represent the condition variable for handling an empty queue "eq"
  attr_accessor :emptye
  # Represent the condition variable for handling a full queue "queue"
  attr_accessor :full
  # Reference a queue that contains all produced items by the producer
  attr_accessor :queue
  # Reference a queue that contains destination numbers to wich the SMS messages couldn't be send
  attr_accessor :eq
  # Represent the max number of items that queue can retain
  attr_accessor :max

  #
  # initialize all variables for the class
  #
  def initialize
    @mutex = Mutex.new
    @mutexp=Mutex.new
    @mutexe=Mutex.new
    @empty = ConditionVariable.new
    @emptye = ConditionVariable.new
    @full = ConditionVariable.new
    @queue = Queue.new
    @eq = Queue.new
    @max = 10
  end

  #
  # Get the number of items for the queue "queue"
  #
  def count
    @queue.size
  end
  
end
