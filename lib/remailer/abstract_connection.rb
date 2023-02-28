class Remailer::AbstractConnection < EventMachine::Connection
  # == Exceptions ===========================================================

  class CallbackArgumentsRequired < Exception; end

  # == Constants ============================================================

  include Remailer::Constants

  DEFAULT_TIMEOUT = 60

  NOTIFICATIONS = [
    :debug,
    :error,
    :connect
  ].freeze

  # == Properties ===========================================================

  attr_accessor :options
  attr_reader :error, :error_message

  # == Extensions ===========================================================

  include EventMachine::Deferrable

  # == Class Methods ========================================================

  # Defines the default timeout for connect operations.
  def self.default_timeout
    DEFAULT_TIMEOUT
  end

  # Opens a connection to a specific server. Options can be specified:
  # * port => Numerical port number
  # * require_tls => If true will fail connections to non-TLS capable
  #   servers (default is false)
  # * username => Username to authenticate with the server
  # * password => Password to authenticate with the server
  # * use_tls => Will use TLS if availble (default is true)
  # * debug => Where to send debugging output (IO or Proc)
  # * connect => Where to send a connection notification (IO or Proc)
  # * error => Where to send errors (IO or Proc)
  # * on_connect => Called upon successful connection (Proc)
  # * on_error => Called upon connection error (Proc)
  # * on_disconnect => Called when connection is closed (Proc)
  # A block can be supplied in which case it will stand in as the :connect
  # option. The block will recieve a first argument that is the status of
  # the connection, and an optional second that is a diagnostic message.
  def self.open(host, options = nil, &block)
    options ||= { }
    options[:host] = host
    options[:port] ||= self.default_port

    unless (options.key?(:use_tls))
      options[:use_tls] = true
    end

    if (block_given?)
      options[:connect] = block
    end

    host_name = host
    host_port = options[:port]

    if (proxy_options = options[:proxy])
      host_name = proxy_options[:host]
      host_port = proxy_options[:port] || SOCKS5_PORT
    end

    establish!(host_name, host_port, options)
  end

  # Warns about supplying a Proc which does not appear to accept the required
  # number of arguments.
  def self.warn_about_arguments(proc, range)
    unless (range.include?(proc.arity) or proc.arity == -1)
      STDERR.puts "Callback must accept #{[ range.min, range.max ].uniq.join(' to ')} arguments but accepts #{proc.arity}"
    end
  end

  def self.establish!(host_name, host_port, options)
    EventMachine.connect(host_name, host_port, self, options)

  rescue EventMachine::ConnectionError => e
    self.report_exception(e, options)

    false
  end

  # Handles callbacks driven by exceptions before an instance could be created.
  def self.report_exception(e, options)
    case (options[:connect])
    when Proc
      options[:connect].call(false, e.to_s)
    when IO
      options[:connect].puts(e.to_s)
    end

    case (options[:on_error])
    when Proc
      options[:on_error].call(e.to_s)
    when IO
      options[:on_error].puts(e.to_s)
    end

    case (options[:debug])
    when Proc
      options[:debug].call(:error, e.to_s)
    when IO
      options[:debug].puts(e.to_s)
    end

    case (options[:error])
    when Proc
      options[:error].call(:connect_error, e.to_s)
    when IO
      options[:error].puts(e.to_s)
    end

    false
  end

  # == Instance Methods =====================================================

  # EventMachine will call this constructor and it is not to be called
  # directly. Use the Remailer::Connection.open method to facilitate the
  # correct creation of a new connection.
  def initialize(options)
    # Throwing exceptions inside this block is going to cause EventMachine
    # to malfunction in a spectacular way and hide the actual exception. To
    # allow for debugging, exceptions are dumped to STDERR as a last resort.
    @options = options
    @hostname = @options[:hostname] || Socket.gethostname
    @timeout = @options[:timeout] || self.class.default_timeout
    @timed_out = false

    @active_message = nil
    @established = false
    @connected = false
    @closed = false
    @unbound = false
    @connecting_to_proxy = false

    @messages = [ ]

    NOTIFICATIONS.each do |type|
      callback = @options[type]

      if (callback.is_a?(Proc))
        self.class.warn_about_arguments(callback, (2..2))
      end
    end

    debug_notification(:options, @options.inspect)

    reset_timeout!

    self.after_initialize

  rescue Object => e
    self.class.report_exception(e, @options)

    STDERR.puts "#{e.class}: #{e}" rescue nil
  end

  def after_complete(&block)
    if (block_given?)
      @options[:after_complete] = block
    elsif (@options[:after_complete])
      @options[:after_complete].call
    end
  end

  # Returns true if the connection requires TLS support, or false otherwise.
  def use_tls?
    !!@options[:use_tls]
  end

  # Returns true if the connection has advertised TLS support, or false if
  # not availble or could not be detected.
  def tls_support?
    !!@tls_support
  end

  # Returns true if the connection has advertised authentication support, or
  # false if not availble or could not be detected. If type is specified,
  # returns true only if that type is supported, false otherwise.
  def auth_support?(type = nil)
    case (type)
    when nil
      !!@auth_support
    else
      !!(@auth_support&.include?(type))
    end
  end

  # Returns true if the connection will be using a proxy to connect, false
  # otherwise.
  def using_proxy?
    !!@options[:proxy]
  end

  # Returns true if the connection will require authentication to complete,
  # that is a username has been supplied in the options, or false otherwise.
  def requires_authentication?
    @options[:username] and !@options[:username].empty?
  end

  # Reassigns the timeout which is specified in seconds. Values equal to
  # or less than zero are ignored and a default is used instead.
  def timeout=(value)
    @timeout = value.to_i
    @timeout = DEFAULT_TIMEOUT if (@timeout <= 0)
  end

  def proxy_connection_initiated!
    @connecting_to_proxy = false
  end

  def proxy_connection_initiated?
    !!@connecting_to_proxy
  end

  # This implements the EventMachine::Connection#completed method by
  # flagging the connection as estasblished.
  def connection_completed
    self.reset_timeout!
  end

  # This implements the EventMachine::Connection#unbind method to capture
  # a connection closed event.
  def unbind
    return if (@unbound)

    self.cancel_timer!

    self.after_unbind

    @unbound = true
    @connected = false
    @timeout_at = nil
    @interpreter = nil

    send_callback(:on_disconnect)
  end

  # Returns true if the connection has been unbound by EventMachine, false
  # otherwise.
  def unbound?
    !!@unbound
  end

  # This implements the EventMachine::Connection#receive_data method that
  # is called each time new data is received from the socket.
  def receive_data(data = nil)
    reset_timeout!

    @buffer ||= ''
    @buffer << data if (data)

    if (interpreter = @interpreter)
      interpreter.process(@buffer) do |reply|
        debug_notification(:receive, "[#{interpreter.label}] #{reply.inspect}")
      end
    else
      error_notification(:out_of_band, "Receiving data before a protocol has been established.")
    end

  rescue Object => e
    self.class.report_exception(e, @options)
    STDERR.puts("[#{e.class}] #{e}") rescue nil

    raise e
  end

  def post_init
    self.set_timer!
  end

  # Returns the current state of the active interpreter, or nil if no state
  # is assigned.
  def state
    if (interpreter = @interpreter)
      @interpreter.state
    else
      nil
    end
  end

  # Sends a single line to the remote host with the appropriate CR+LF
  # delmiter at the end.
  def send_line(line = '')
    reset_timeout!

    send_data(line + CRLF)

    debug_notification(:send, line.inspect)
  end

  def resolve_hostname(hostname)
    record = Socket.gethostbyname(hostname)

    # FIXME: IPv6 Support here
    address = (record and record[3])

    if (address)
      debug_notification(:resolver, "Address #{hostname} resolved as #{address.unpack('CCCC').join('.')}")
    else
      debug_notification(:resolver, "Address #{hostname} could not be resolved")
    end

    yield(address) if (block_given?)

    address
  rescue
    nil
  end

  # Resets the timeout time. Returns the time at which a timeout will occur.
  def reset_timeout!
    @timeout_at = Time.now + @timeout
  end

  # Returns the number of seconds remaining until a timeout will occur, or
  # nil if no time-out is pending.
  def time_remaning
    @timeout_at and (@timeout_at.to_i - Time.now.to_i)
  end

  def set_timer!
    @timer = EventMachine.add_periodic_timer(1) do
      self.check_for_timeouts!
    end
  end

  def cancel_timer!
    if (@timer)
      @timer.cancel
      @timer = nil
    end
  end

  # Checks for a timeout condition, and if one is detected, will close the
  # connection and send appropriate callbacks.
  def check_for_timeouts!
    return if (!@timeout_at or Time.now < @timeout_at or @timed_out)

    @timed_out = true
    @timeout_at = nil

    if (@connected and @active_message)
      message_callback(:timeout, "Response timed out before send could complete")
      error_notification(:timeout, "Response timed out")
      debug_notification(:timeout, "Response timed out")
      send_callback(:on_error)
    elsif (!@connected)
      remote_options = @options
      interpreter = @interpreter

      if (self.proxy_connection_initiated?)
        remote_options = @options[:proxy]
      end

      message = "Timed out before a connection could be established to #{remote_options[:host]}:#{remote_options[:port]}"

      if (interpreter)
        message << " using #{interpreter.label}"
      end

      connect_notification(false, message)
      debug_notification(:timeout, message)
      error_notification(:timeout, message)

      send_callback(:on_error)
    else
      interpreter = @interpreter

      if (interpreter and interpreter.respond_to?(:close))
        interpreter.close
      else
        send_callback(:on_disconnect)
      end
    end

    self.close_connection
  end

  # Returns true if the connection has been closed, false otherwise.
  def closed?
    !!@closed
  end

  # Returns true if an error has occurred, false otherwise.
  def error?
    !!@error
  end

  # EventMachine: Closes down the connection.
  def close_connection
    return if (@closed)

    unless (@timed_out)
      send_callback(:on_disconnect)
    end

    debug_notification(:closed, "Connection closed")

    super

    @connected = false
    @closed = true
    @timeout_at = nil
    @interpreter = nil
  end
  alias_method :close, :close_connection

  def after_ready
    @established = true

    reset_timeout!
  end

  # -- Callbacks and Notifications ------------------------------------------

  def interpreter_entered_state(interpreter, state)
    debug_notification(:state, "#{interpreter.label.downcase}=#{state}")
  end

  def send_notification(type, code, message)
    case (callback = @options[type])
    when nil, false
      # No notification in this case
    when Proc
      callback.call(code, message)
    when IO
      callback.puts("%s: %s" % [ code.to_s, message ])
    else
      STDERR.puts("%s: %s" % [ code.to_s, message ])
    end
  end

  # EventMachine: Enables TLS support on the connection.
  def start_tls
    debug_notification(:tls, "Started")
    super
  end

  def connected?
    @connected
  end

  def connect_notification(code, message = nil)
    @connected = code

    send_notification(:connect, code, message || self.remote)

    if (code)
      send_callback(:on_connect)
    end
  end

  def error_notification(code, message)
    @error = code
    @error_message = message

    send_notification(:error, code, message)
  end

  def debug_notification(code, message)
    send_notification(:debug, code, message)
  end

  def message_callback(reply_code, reply_message)
    active_message = @active_message

    if (callback = (active_message and active_message[:callback]))
      # The callback is screened in advance when assigned to ensure that it
      # has only 1 or 2 arguments. There should be no else here.
      case (callback.arity)
      when 2
        callback.call(reply_code, reply_message)
      when 1
        callback.call(reply_code)
      end
    end
  end

  def send_callback(type)
    if (callback = @options[type])
      case (callback.arity)
      when 1
        callback.call(self)
      else
        callback.call
      end
    end
  end
end
