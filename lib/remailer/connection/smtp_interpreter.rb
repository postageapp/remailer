class Remailer::Connection::SmtpInterpreter < Remailer::Interpreter
  # == Constants ============================================================

  LINE_REGEXP = /^.*?\r?\n/.freeze

  # == Properties ===========================================================

  # == Class Methods ========================================================
  
  # Expands a standard SMTP reply into three parts: Numerical code, message
  # and a boolean indicating if this reply is continued on a subsequent line.
  def self.split_reply(reply)
    reply.match(/(\d+)([ \-])(.*)/) and [ $1.to_i, $3, $2 == '-' ? :continued : nil ].compact
  end

  # Encodes the given user authentication paramters as a Base64-encoded
  # string as defined by RFC4954
  def self.encode_authentication(username, password)
    base64("\0#{username}\0#{password}")
  end
  
  # Encodes the given data for an RFC5321-compliant stream where lines with
  # leading period chracters are escaped.
  def self.encode_data(data)
    data.gsub(/((?:\r\n|\n)\.)/m, '\\1.')
  end

  # Encodes a string in Base64 as a single line
  def self.base64(string)
    [ string.to_s ].pack('m').chomp
  end
  
  # == State Mapping ========================================================
  
  parse(LINE_REGEXP) do |data|
    split_reply(data.chomp)
  end
  
  state :initialized do
    interpret(220) do |message, continues|
      message_parts = message.split(/\s+/)
      delegate.remote = message_parts.first
      
      if (message.match(/\bESMTP\b/))
        delegate.protocol = :esmtp
      end

      unless (continues)
        case (delegate.protocol)
        when :esmtp
          enter_state(:ehlo)
        else
          enter_state(:helo)
        end
      end
    end
    
    interpret(421) do |message|
      delegate.connect_notification(false, "Connection timed out")
      delegate.debug_notification(:error, "[#{@state}] 421 #{message}")
      delegate.error_notification(421, message)
      delegate.send_callback(:on_error)

      enter_state(:terminated)
    end
  end
  
  state :helo do
    enter do
      delegate.send_line("HELO #{delegate.hostname}")
    end

    interpret(250) do
      if (delegate.requires_authentication?)
        enter_state(:auth)
      else
        enter_state(:established)
      end
    end
  end
  
  state :ehlo do
    enter do
      delegate.send_line("EHLO #{delegate.hostname}")
    end

    interpret(250) do |message, continues|
      message_parts = message.split(/\s+/)

      case (message_parts[0].to_s.upcase)
      when 'SIZE'
        delegate.max_size = message_parts[1].to_i
      when 'PIPELINING'
        delegate.pipelining = true
      when 'STARTTLS'
        delegate.tls_support = true
      when 'AUTH'
        delegate.auth_support = message_parts[1, message_parts.length].inject({ }) do |h, v|
          h[v] = true
          h
        end
      end

      unless (continues)
        if (delegate.use_tls? and delegate.tls_support?)
          enter_state(:starttls)
        elsif (delegate.requires_authentication?)
          enter_state(:auth)
        else
          enter_state(:established)
        end
      end
    end
  end
  
  state :starttls do
    enter do
      delegate.send_line("STARTTLS")
    end
    
    interpret(220) do
      delegate.start_tls
      
      enter_state(:helo)
    end
  end

  state :auth do
    enter do
      delegate.send_line("AUTH PLAIN #{self.class.encode_authentication(delegate.options[:username], delegate.options[:password])}")
    end
    
    interpret(235) do
      enter_state(:established)
    end
    
    interpret(535) do |message, continues|
      if (@error)
        @error << ' '
        
        if (message.match(/^(\S+)/).to_s == @error.match(/^(\S+)/).to_s)
          @error << message.sub(/^\S+/, '')
        else
          @error << message
        end
      else
        @error = message
      end

      unless (continues)
        enter_state(:quit)
      end
    end
  end
  
  state :established do
    enter do
      delegate.connect_notification(true)
      
      enter_state(:ready)
    end
  end
  
  state :ready do
    enter do
      delegate.after_ready
    end
  end
  
  state :send do
    enter do
      enter_state(:mail_from)
    end
  end
  
  state :mail_from do
    enter do
      if (delegate.active_message)
        delegate.send_line("MAIL FROM:<#{delegate.active_message[:from]}>")
      else
        delegate.message_callback(false, "Delegate has no active message")
        enter_state(:reset)
      end
    end

    interpret(250) do
      enter_state(:rcpt_to)
    end
    
    interpret(503) do |message, continues|
      if (message.match(/5\.5\.1/))
        enter_state(:re_helo)
      end
    end
  end
  
  state :re_helo do
    enter do
      delegate.send_line("HELO #{delegate.hostname}")
    end
    
    interpret(250) do
      enter_state(:mail_from)
    end
  end
  
  state :rcpt_to do
    enter do
      if (delegate.active_message)
        delegate.send_line("RCPT TO:<#{delegate.active_message[:to]}>")
      else
        delegate.message_callback(false, "Delegate has no active message")
        enter_state(:reset)
      end
    end
    
    interpret(250) do
      if (delegate.active_message[:test])
        delegate_call(:after_message_sent, reply_code, reply_message)

        enter_state(:reset)
      else
        enter_state(:data)
      end
    end
  end
  
  state :data do
    enter do
      delegate.send_line("DATA")
    end
    
    interpret(354) do
      enter_state(:sending)
    end
  end
  
  state :sending do
    enter do
      data = delegate.active_message[:data]

      delegate.debug_notification(:send, data.inspect)

      delegate.send_data(self.class.encode_data(data))

      # Ensure that a blank line is sent after the last bit of email content
      # to ensure that the dot is on its own line.
      delegate.send_line
      delegate.send_line(".")
    end
    
    default do |reply_code, reply_message|
      delegate_call(:after_message_sent, reply_code, reply_message)

      enter_state(:sent)
    end
  end
  
  state :sent do
    enter do
      enter_state(:ready)
    end
  end
  
  state :quit do
    enter do
      delegate.send_line("QUIT")
    end
    
    interpret(221) do
      enter_state(:terminated)
    end
  end
  
  state :terminated do
    enter do
      delegate.close_connection
    end
  end
  
  state :reset do
    enter do
      delegate.send_line("RSET")
    end
    
    interpret(250) do
      enter_state(:ready)
    end
  end
  
  state :noop do
    enter do
      delegate.send_line("NOOP")
    end
    
    interpret(250) do
      enter_state(:ready)
    end
  end
  
  on_error do |reply_code, reply_message|
    delegate.message_callback(reply_code, reply_message)
    delegate.debug_notification(:error, "[#{@state}] #{reply_code} #{reply_message}")
    delegate.error_notification(reply_code, reply_message)
    
    delegate.active_message = nil
    
    enter_state(delegate.protocol ? :reset : :terminated)
  end

  # == Instance Methods =====================================================

  def label
    'SMTP'
  end

  def will_interpret?(proc, args)
    # Can only interpret blocks if the last part of the message has been
    # received. The continue flag is argument index 1. This will only apply
    # to interpret blocks that do not receive arguments.
  
    (proc.arity == 0) ? !args[1] : true
  end
end
