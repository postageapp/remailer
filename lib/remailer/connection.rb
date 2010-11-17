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
  attr_reader :remote, :max_size, :protocol

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
  
  def self.encode_data(data)
    data.gsub(/((?:\r\n|\n)\.)/m, '\\1.')
  end

  # == Instance Methods =====================================================
  
  def initialize(options)
    @options = options

    @options[:hostname] ||= Socket.gethostname
    @messages = [ ]
    
    debug_notification(:options, @options.inspect)
    
    @timeout_at = Time.now + (@timeout || DEFAULT_TIMEOUT)
  end
  
  # Returns true if the connection has advertised TLS support, or false if
  # not availble or could not be detected. This will only work with ESMTP
  # capable servers.
  def tls_support?
    !!@tls_support
  end

  # This is used to create a callback that will be called if no more messages
  # are schedueld to be sent.
  def after_complete(&block)
    @options[:after_complete] = block
  end
  
  def close_when_complete!
    @options[:close] = true
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
    @state = :connected
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

  def post_init
    @state = :connecting
  
    EventMachine.add_periodic_timer(1) do
      check_for_timeouts!
    end
  end

  def send_line(line = '')
    send_data(line + CRLF)

    debug_notification(:send, line.inspect)
  end

  # Returns true if the reply has been completed, or false if it is still
  # in the process of being received.
  def reply_complete?
    !!@reply_complete
  end
  
  def receive_reply(reply)
    debug_notification(:reply, reply.inspect)

    return unless (reply)
    
    if (reply.match(/(\d+)([ \-])(.*)/))
      reply_code = $1.to_i
      @reply_complete = $2 != '-'
      reply_message = $3
    end
    
    case (state)
    when :connected
      case (reply_code)
      when 220
        reply_parts = reply_message.split(/\s+/)
        @remote = reply_parts.first
        
        if (reply_parts.include?('ESMTP'))
          @state = :sent_ehlo
          @protocol = :esmtp
          send_line("EHLO #{@options[:hostname]}")
        else
          @state = :sent_helo
          @protocol = :smtp
          send_line("HELO #{@options[:hostname]}")
        end
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_ehlo
      case (reply_code)
      when 250
        reply_parts = reply_message.split(/\s+/)
        case (reply_parts[0].to_s.upcase)
        when 'SIZE'
          @max_size = reply_parts[1].to_i
        when 'PIPELINING'
          @pipelining = true
        when 'STARTTLS'
          @tls_support = true
        end
      
        # FIX: Add TLS support
        #        if (@tls_support and @options[:use_tls])
        #          @state = :tls_init
        #        end

        if (@reply_complete)
          # Add authentication hook
          @state = :ready

          send_queued_message!
        end
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_helo
      case (reply_code)
      when 250
        @state = :ready
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_mail_from
      case (reply_code)
      when 250
        @state = :sent_rcpt_to
        send_line("RCPT TO:#{@active_message[:to]}")
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_rcpt_to
      case (reply_code)
      when 250
        @state = :sent_data
        send_line("DATA")
        
        @data_offset = 0
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_data
      case (reply_code)
      when 354
        @state = :data_sending
        
        transmit_data_chunk!
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_data_content
      if (callback = @active_message[:callback])
        callback.call(reply_code)
      end
      
      @state = :ready
      
      send_queued_message!
    when :sent_quit
      case (reply_code)
      when 221
        @state = :closed
        close_connection
      else
        fail_unanticipated_response!(reply)
      end
    when :sent_reset
      case (reply_code)
      when 250
        @state = :ready
        
        
        send_queued_message!
      end
    end
  end
  
  def transmit_data_chunk!(chunk_size = nil)
    data = @active_message[:data]
    chunk_size ||= data.length
    
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
  
  def notify_writable
    # FIXME: Get EventMachine to trigger this
  end

  def send_queued_message!
    return if (@active_message)
      
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

    callback(nil)
    @state = :timeout
    close_connection
  end
  
  def debug_notification(type, message)
    case (@options[:debug])
    when nil, false
      # No debugging in this case
    when Proc
      @options[:debug].call(type, message)
    when IO
      @options[:debug].puts("%s: %s" % [ type, message ])
    else
      STDERR.puts("%s: %s" % [ type, message ])
    end
  end
  
  def fail_unanticipated_response!(reply)
    if (@active_message)
      if (callback = @active_message[:callback])
        callback.call(nil)
      end
    end
    
    @active_message = nil
    
    @state = :sent_reset
    send_line("RESET")
  end
end
