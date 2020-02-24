require 'socket'
require 'eventmachine'

class Remailer::SMTP::Server < EventMachine::Protocols::LineAndTextProtocol
  # == Submodules ===========================================================
  
  autoload(:Interpreter, 'remailer/smtp/server/interpreter')
  autoload(:Transaction, 'remailer/smtp/server/transaction')

  # == Constants ============================================================
  
  DEFAULT_BIND_ADDR = '0.0.0.0'.freeze

  # == Extensions ===========================================================
  
  include Remailer::Constants

  # == Properties ===========================================================
  
  attr_accessor :logger
  attr_reader :server_name, :quirks
  attr_reader :remote_ip, :remote_port, :remote_name
  attr_reader :local_ip, :local_port
  attr_reader :local_config
  
  attr_accessor :private_key_path
  attr_accessor :ssl_cert_path
  
  # == Class Methods ========================================================
  
  # This returns the hostname for the specified IP if one is to be assigned.
  # The default is to return the IP as-is, but this can be customized in
  # a subclass.
  def self.hostname(ip)
    ip
  end
  
  def self.hostname_for_ip(ip)
    nil
  end
  
  def self.bind(bind_addr = nil, port = nil, options = nil)
    EventMachine.start_server(
      bind_addr || DEFAULT_BIND_ADDR,
      port || SMTP_PORT,
      self,
      options
    )
  end

  # == Instance Methods =====================================================
  
  def initialize(options = nil)
    super
    
    @options = options || { }

    @remote_port, @remote_ip = Socket.unpack_sockaddr_in(get_peername)
    @local_port, @local_ip = Socket.unpack_sockaddr_in(get_sockname)
    
    @server_name = @options[:server_name] || self.class.hostname(@local_ip) || @local_ip

    @logger = nil
    @remote_host = nil
    @tls_support = false
    @interpreter_class = options && options[:interpreter] || Interpreter

    log(:debug, "Connection from #{@remote_ip}:#{@remote_port} to #{@local_ip}:#{@local_port}")
    
    @on_transaction = @options[:on_transaction]
    @on_connect = @options[:on_connect]
  end
  
  def post_init
    super

    @interpreter = @interpreter_class.new(delegate: self)
    
    if (@on_connect)
      @on_connect.call(@remote_ip)
    end
  end
  
  def on_transaction(&block)
    @on_transaction = block
  end
  
  def receive_line(line)
    @interpreter.process(line)

  rescue Object => e
    STDERR.puts("#{e.class}: #{e}")
  end
  
  def log(level, message)
    @logger and @logger.send(level, message)
  end
  
  def unbind
    super
    
    log(:debug, "Connection from #{@remote_ip} to #{@local_ip} closed")
  end
  
  def send_line(line)
    send_data(line + CRLF)
  end
  
  def tls?
    ENV['TLS'] and self.private_key_path and self.ssl_cert_path
  end
  
  def remote_host
    @remote_host
  end
  
  # This is called with the transaction state established by the SMTP
  # client. The return value should be the response code and message
  # sent back to the client.
  def receive_transaction(transaction)
    if (@on_transaction)
      @on_transaction.call(transaction)
    end
    
    [ true, "250 Message received" ]
  end
  
  def check_for_timeout!
    @interpreter.check_for_timeout!
  end
  
  def validate_hostname(remote_host)
    yield(true) if (block_given?)
  end
end
