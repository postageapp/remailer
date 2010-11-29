require 'socket'
require 'eventmachine'

class Remailer::Connection < EventMachine::Connection
  # == Exceptions ===========================================================
  
  class CallbackArgumentsRequired < Exception; end

  # == Submodules ===========================================================
  
  autoload(:SmtpInterpreter, 'remailer/connection/smtp_interpreter')

  # == Constants ============================================================
  
  DEFAULT_TIMEOUT = 5
  CRLF = "\r\n".freeze
  CRLF_LENGTH = CRLF.length

  SMTP_PORT = 25
  SOCKS5_PORT = 1080
  
  SOCKS5_VERSION = 5

  SOCKS5_METHOD = {
    :no_auth => 0,
    :gssapi => 1,
    :username_password => 2
  }.freeze
  
  SOCKS5_COMMAND = {
    :connect => 1,
    :bind => 2
  }.freeze
  
  SOCKS5_REPLY = {
    0 => 'Succeeded',
    1 => 'General SOCKS server failure',
    2 => 'Connection not allowed',
    3 => 'Network unreachable',
    4 => 'Host unreachable',
    5 => 'Connection refused',
    6 => 'TTL expired',
    7 => 'Command not supported',
    8 => 'Address type not supported'
  }.freeze
  
  SOCKS5_ADDRESS_TYPE = {
    :ipv4 => 1,
    :domainname => 3,
    :ipv6 => 4
  }.freeze
  
  NOTIFICATIONS = [
    :debug,
    :error,
    :connect
  ].freeze
  
  # == Properties ===========================================================
  
  attr_reader :state, :mode
  attr_reader :remote, :max_size, :protocol
  attr_accessor :timeout
  attr_accessor :options

  # == Extensions ===========================================================

  include EventMachine::Deferrable

  # == Class Methods ========================================================

  # Opens a connection to a specific SMTP server. Options can be specified:
  # * port => Numerical port number (default is 25)
  # * require_tls => If true will fail connections to non-TLS capable
  #   servers (default is false)
  # * use_tls => Will use TLS if availble (default is true)
  def self.open(smtp_server, options = nil)
    options ||= { }
    options[:host] = smtp_server
    options[:port] ||= 25
    options[:use_tls] = true unless (options.key?(:use_tls))
    
    host_name = smtp_server
    host_port = options[:port]
    
    if (proxy_options = options[:proxy])
      host_name = proxy_options[:host]
      host_port = proxy_options[:port] || SOCKS5_PORT
    end

    EventMachine.connect(host_name, host_port, self, options)
  end
  
  def self.encode_data(data)
    data.gsub(/((?:\r\n|\n)\.)/m, '\\1.')
  end
  
  def self.base64(string)
    [ string.to_s ].pack('m').chomp
  end
  
  def self.encode_authentication(username, password)
    base64("\0#{username}\0#{password}")
  end
  
  def self.warn_about_arguments(proc, range)
    unless (range.include?(proc.arity) or proc.arity == -1)
      STDERR.puts "Callback must accept #{[ range.min, range.max ].uniq.join(' to ')} arguments but accepts #{proc.arity}"
    end
  end
  
  def self.split_reply(reply)
    reply.match(/(\d+)([ \-])(.*)/) and [ $1.to_i, $3, $2 == '-' ]
  end

  # == Instance Methods =====================================================
  
  def initialize(options)
    # Throwing exceptions inside this block is going to cause EventMachine
    # to malfunction in a spectacular way and hide the actual exception. To
    # allow for debugging, exceptions are dumped to STDERR as a last resort.
    @options = options

    @options[:hostname] ||= Socket.gethostname
    @messages = [ ]
    
    @state = Remailer::Connection::State.new
  
    NOTIFICATIONS.each do |type|
      callback = @options[type]

      if (callback.is_a?(Proc))
        self.class.warn_about_arguments(callback, (2..2))
      end
    end
  
    debug_notification(:options, @options.inspect)
  
    reset_timeout!
  rescue Object => e
    STDERR.puts "#{e.class}: #{e}"
  end
  
  # Returns true if the connection has advertised TLS support, or false if
  # not availble or could not be detected. This will only work with ESMTP
  # capable servers.
  def tls_support?
    !!@tls_support
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

  # This is used to create a callback that will be called if no more messages
  # are schedueld to be sent.
  def after_complete(&block)
    @options[:after_complete] = block
  end
  
  # Closes the connection after all of the queued messages have been sent.
  def close_when_complete!
    @options[:close] = true
  end

  # Sends an email message through the connection at the earliest opportunity.
  # A callback block can be supplied that will be executed when the message
  # has been sent, an unexpected result occurred, or the send timed out.
  def send_email(from, to, data, &block)
    if (block_given?)
      self.class.warn_about_arguments(block, 1..2)
    end
    
    message = {
      :from => from,
      :to => to,
      :data => data,
      :callback => block
    }
    
    @messages << message
    
    # If the connection is ready to send...
    if (@state == :ready)
      # ...send the message right away.
      send_queued_message!
    end
  end
  
  # Returns the details of the active message being sent, or nil if no message
  # is being sent.
  def active_message
    @active_message
  end
  
  # Reassigns the timeout which is specified in seconds. Values equal to
  # or less than zero are ignored and a default is used instead.
  def timeout=(value)
    @timeout = value.to_i
    @timeout = DEFAULT_TIMEOUT if (@timeout <= 0)
  end
  
  # This implements the EventMachine::Connection#completed method by
  # flagging the connection as estasblished.
  def connection_completed
    @timeout_at = nil
    
    if (using_proxy?)
      enter_proxy_init_state!
    else
      connect_notification(true, "Connection completed")
      @state = :connected
      @connected = true
    end
  end
  
  # This implements the EventMachine::Connection#unbind method to capture
  # a connection closed event.
  def unbind
    @state = :closed
    
    if (@active_message)
      if (callback = @active_message[:callback])
        callback.call(nil)
      end
    end
  end

  def receive_data(data)
    # FIX: Buffer the data anyway.
    
    case (state)
    when :proxy_init
      version, method = data.unpack('CC')
      
      if (method == SOCKS5_METHOD[:username_password])
        enter_proxy_authentication_state!
      else
        enter_proxy_connecting_state!
      end
    when :proxy_connecting
      version, reply, reserved, address_type, address, port = data.unpack('CCCCNn')
      
      case (reply)
      when 0
        @state = :connected
        @connected = true
        connect_notification(true, "Connection completed")
      else
        debug(:error, "Proxy server returned error code #{reply}: #{SOCKS5_REPLY[reply]}")
        connect_notification(false, "Proxy server returned error code #{reply}: #{SOCKS5_REPLY[reply]}")
        close_connection
        @state = :failed
      end
    when :proxy_authenticating
      # Decode response of authentication request...
      
      # ...
    else
      # Data is received in arbitrary sized chunks, so there is no guarantee
      # a whole line will be ready to process, or that there is only one line.
      @buffer ||= ''
      @buffer << data
    
      while (line_index = @buffer.index(CRLF))
        if (line_index > 0)
          receive_reply(@buffer[0, line_index])
        end

        @buffer = (@buffer[line_index + CRLF_LENGTH, @buffer.length] || '')
      end
    end
  end

  def post_init
    @state = :connecting
  
    EventMachine.add_periodic_timer(1) do
      check_for_timeouts!
    end
  end

protected
  def send_line(line = '')
    send_data(line + CRLF)

    debug_notification(:send, line.inspect)
  end

  # Returns true if the reply has been completed, or false if it is still
  # in the process of being received.
  def reply_complete?
    !!@reply_complete
  end
  
  def resolve_hostname(hostname)
    # FIXME: Elminitate this potentially blocking call by using an async
    #        resolver if available.
    record = Socket.gethostbyname(hostname)
    
    debug_notification(:resolved, record && record.last)

    record and record.last
  rescue
    nil
  end

  def receive_reply(reply)
    debug_notification(:reply, reply.inspect)

    return unless (reply)
    
    reply_code, reply_message, @reply_continued = self.class.split_reply(reply)
    
    @state.receive_reply(reply_code, reply_message)
  end
  
  def enter_proxy_init_state!
    debug_notification(:proxy, "Initiating proxy connection through #{@options[:proxy][:host]}")

    socks_methods = [ ]
    
    if (@options[:proxy][:username])
      socks_methods << SOCKS5_METHOD[:username_password]
    end
    
    send_data(
      [
        SOCKS5_VERSION,
        socks_methods.length,
        socks_methods
      ].flatten.pack('CCC*')
    )

    @state = :proxy_init
  end
  
  def enter_proxy_connecting_state!
    # REFACTOR: Move the resolution of the hostname to an earlier point to
    #           avoid connecting needlessly.
    
    debug_notification(:proxy, "Sending proxy connection request to #{@options[:host]}:#{@options[:port]}")
    
    if (ip_address = resolve_hostname(@options[:host]))
      send_data(
        [
          SOCKS5_VERSION,
          SOCKS5_COMMAND[:connect],
          0,
          SOCKS5_ADDRESS_TYPE[:ipv4],
          ip_address,
          @options[:port]
        ].pack('CCCCA4n')
      )
      
      @state = :proxy_connecting
    else
      send_callback(:error_connecting, "Could not resolve hostname #{@options[:host]}")
      
      @state = :failed
      close_connection
    end
  end
  
  def enter_proxy_authenticating_state!
    debug_notification(:proxy, "Sending proxy authentication")

    proxy_options = @options[:proxy]
    username = proxy_options[:username]
    password = proxy_options[:password]
    
    send_data(
      [
        SOCKS5_VERSION,
        username.length,
        username,
        password.length,
        password
      ].pack('CCA*CA*')
    )
    
    @state = :proxy_authenticating
  end
  
  def enter_ready_state!
    @state = :ready
    
    send_queued_message!
  end
  
  def transmit_data!(chunk_size = nil)
    data = @active_message[:data]
    chunk_size ||= data.length
    
    # This chunk-based sending will work better when/if EventMachine can be
    # configured to support 'writable' notifications on the active socket.
    chunk = data[@data_offset, chunk_size]
    debug_notification(:send, chunk.inspect)
    send_data(self.class.encode_data(data))
    @data_offset += chunk_size
    
    if (@data_offset >= data.length)
      @state = :sent_data_content

      # Ensure that a blank line is sent after the last bit of email content
      # to ensure that the dot is on its own line.
      send_line
      send_line(".")
    end
  end
  
  def reset_timeout!
    @timeout_at = Time.now + (@options[:timeout] || DEFAULT_TIMEOUT)
  end

  def send_queued_message!
    return if (@active_message)
    
    reset_timeout!
      
    if (@active_message = @messages.shift)
      @state = :sent_mail_from
      send_line("MAIL FROM:#{@active_message[:from]}")
    elsif (@options[:close])
      if (callback = @options[:after_complete])
        callback.call
      end

      send_line("QUIT")
      @state = :sent_quit
    end
  end

  def check_for_timeouts!
    return if (!@timeout_at or Time.now < @timeout_at)

    error_notification(:timeout, "Connection timed out")
    debug_notification(:timeout, "Connection timed out")
    send_callback(:timeout, "Connection timed out before send could complete")

    @state = :timeout

    unless (@connected)
      connect_notification(false, "Connection timed out")
    end

    close_connection
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
  
  def connect_notification(code, message)
    send_notification(:connect, code, message)
  end

  def error_notification(code, message)
    send_notification(:error, code, message)
  end

  def debug_notification(code, message)
    send_notification(:debug, code, message)
  end

  def send_callback(reply_code, reply_message)
    if (callback = (@active_message and @active_message[:callback]))
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
  
  def fail_unanticipated_response!(reply_code, reply_message)
    send_callback(reply_code, reply_message)
    debug_notification(:error, "[#{@state}] #{reply_code} #{reply_message}")
    error_notification(reply_code, reply_message)
    
    @active_message = nil
    
    @state = :sent_reset
    send_line("RESET")
  end
end
