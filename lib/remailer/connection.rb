require 'socket'
require 'eventmachine'

class Remailer::Connection < EventMachine::Connection
  # == Constants ============================================================
  
  DEFAULT_TIMEOUT = 5
  SMTP_PORT = 25
  CRLF = "\r\n".freeze
  CRLF_LENGTH = CRLF.length
  
  # == Properties ===========================================================
  
  attr_accessor :timeout
  attr_reader :state, :mode
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
    options[:port] ||= 25
    options[:use_tls] = true unless (options.key?(:use_tls))
    
    puts "CONNECT #{smtp_server}:#{options[:port]} with #{self}" if (options[:debug])

    EventMachine.connect(smtp_server, options[:port], self, options)
  end
  
  # EHLO address
  # MAIL FROM:<reverse-path> [SP <mail-parameters> ] <CRLF>
  # RCPT TO:<forward-path> [ SP <rcpt-parameters> ] <CRLF>
  # DATA <CRLF>
  # NOOP
  # QUIT
  
  # 250-mx.google.com at your service, [99.231.152.248]
  # 250-SIZE 35651584
  # 250-8BITMIME
  # 250-STARTTLS
  # 250 ENHANCEDSTATUSCODES

  # == Instance Methods =====================================================
  
  def initialize(options)
    @options = options

    @options[:hostname] ||= Socket.gethostname
    @messages = [ ]
    
    puts "OPTIONS: #{@options}" if (@options[:debug])
    
    @timeout_at = Time.now + (@timeout || DEFAULT_TIMEOUT)
  end
  
  def send_line(line = '')
    send_data(line + CRLF)

    puts "-> #{line.inspect}" if (@options[:debug])
  end
  
  def post_init
    @state = :connecting
  
    EventMachine.add_periodic_timer(1) do
      check_for_timeouts!
    end
  end
  
  def connection_completed
    @timeout_at = nil
    @state = :connected
    @mode = :response
  end
  
  def unbind
    @state = :closed
  end
  
  def send_email(from, to, data, &block)
    message = {
      :from => from,
      :to => to,
      :data => data,
      :callback => block
    }
    
    @messages << message
    
    if (@state == :ready)
      send_queued_message!
    end
  end
  
  def active_message
    @active_message
  end
  
  def receive_data(data)
    @buffer ||= ''
    @buffer << data
    
    while (line_index = @buffer.index(CRLF))
      if (line_index > 0)
        receive_line(@buffer[0, line_index])
      end

      @buffer = (@buffer[line_index + CRLF_LENGTH, @buffer.length] || '')
    end
  end
  
  def receive_line(line)
    puts "+> #{line.inspect}" if (@options[:debug])

    return unless (line)
    
    case (state)
    when :connected
      if (line.match(/^220 (\S+) ESMTP/))
        @state = :ehello
        @remote = $1
        send_line("EHLO #{@options[:hostname]}")
      end
    when :ehello
      if (line.match(/250[ \-]SIZE (\d+)/))
        @max_size = $1.to_i
      elsif (line.match(/250[ \-]PIPELINING/))
        @pipelining = true
      elsif (line.match(/250[ \-]STARTTLS/))
        @tls_support = true
      end
      
      # A space after the code indicates the mutli-line response is finished
      if (line.match(/250 /))
#        if (@tls_support and @options[:use_tls])
#          @state = :tls_init
#        end

        # FIX: Add authentication hook here
        @state = :ready
        
        send_queued_message!
      end
    when :mail_from
      if (line.match(/250 /))
        @state = :rcpt_to
        send_line("RCPT TO:#{@active_message[:to]}")
      end
    when :rcpt_to
      if (line.match(/250 /))
        @state = :data_pending
        send_line("DATA")
        
        @data_offset = 0
      end
    when :data_pending
      if (line.match(/354/))
        @state = :data_sending
        
        transmit_data_chunk!
      end
    when :data_sent
      if (line.match(/(\d+) /))
        result = $1.to_i
        
        if (callback = @active_message[:callback])
          callback.call(result)
        end
        
        @state = :ready
        
        send_queued_message!
      end
    when :closing
      if (line.match(/221/))
        @state = :closed
        close_connection
      end
    end
  end
  
  def transmit_data_chunk!(chunk_size = nil)
    # FIX: Data will need to be properly formatted here, with the "dot"
    # encoding handled as per RFC.
    
    data = @active_message[:data]
    chunk_size ||= data.length
    
    chunk = data[@data_offset, chunk_size]
    puts "-> " + chunk.inspect if (@options[:debug])
    send_data(chunk)
    @data_offset += chunk_size
    
    if (@data_offset >= data.length)
      # Ensure that a blank line is sent after the last bit of email content
      # to ensure that the dot is on its own line.
      send_line
      send_line(".")
      @state = :data_sent
    end
  end
  
  def notify_writable
    # FIXME: Get EventMachine to trigger this
  end

  def send_queued_message!
    return if (@active_message)
      
    if (@active_message = @messages.shift)
      @state = :mail_from
      send_line("MAIL FROM:#{@active_message[:from]}")
    elsif (@options[:close])
      send_line("QUIT")
      @state = :closing
    end
  end

  def check_for_timeouts!
    return if (!@timeout_at or Time.now < @timeout_at)

    # ...
  end
  
  def timeout=(value)
    @timeout = value.to_i
    @timeout = DEFAULT_TIMEOUT if (@timeout <= 0)
  end
end
