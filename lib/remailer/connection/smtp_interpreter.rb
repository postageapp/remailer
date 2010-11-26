class Remailer::Connection::SmtpInterpreter < Remailer::Interpreter
  # == Constants ============================================================

  # == Properties ===========================================================

  attr_reader :remote, :protocol
  attr_reader :max_size, :pipelining, :tls_support

  # == Configuration ========================================================
  
  state :connected do
    interpret(220) do |message|
      message_parts = message.split(/\s+/)
      @remote = message_parts.first
    
      if (message_parts.include?('ESMTP'))
        @protocol = :esmtp
        enter_state(:ehlo)
      else
        @protocol = :smtp
        enter_state(:helo)
      end
    end
  end
  
  state :helo do
    enter do
      delegate.send_line("HELO #{delegate.hostname}")
    end

    interpret(250) do
      enter_state(:ready)
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
        @max_size = reply_parts[1].to_i
      when 'PIPELINING'
        @pipelining = true
      when 'STARTTLS'
        @tls_support = true
      end

      unless (continues)
        if (delegate.use_tls?)
          enter_state(:starttls)
        elsif (delegate.requires_authentication?)
          enter_state(:auth)
        else
          enter_state(:ready)
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
      
      if (delegate.requires_authentication?)
        enter_sent_auth_state!
      else
        enter_ready_state!
      end
    end
  end

  state :auth do
    enter do
      delegate.send_line("AUTH PLAIN #{delegate.class.encode_authentication(delegate.options[:username], delegate.options[:password])}")
    end
    
    interpret(235) do
      enter_state(:ready)
    end
  end
  
  state :ready do
    # This is a holding state, nothing is expected to happen here
  end
  
  state :mail_from do
    enter do
      delegate.send_line("MAIL FROM:#{delegate.active_message[:from]}")
    end

    interpret(250) do
      enter_state(:rcpt_to)
    end
  end
  
  state :rcpt_to do
    enter do
      delegate.send_line("RCPT TO:#{delegate.active_message[:to]}")
    end
    
    interpret(250) do
      enter_state(:data)
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
      delegate.transmit_data!
    end
    
    default do |reply_code, reply_message|
      delegate.send_callback(reply_code, reply_message)
      enter_state(:ready)
    end
  end
  
  state :quit do
    enter do
    end
    
    interpret(221) do
      enter_state(:closed)
      delegate.close_connection
    end
  end
  
  state :reset do
    enter do
      delegate.send_line("RESET")
    end
    
    interpret(250) do
      enter_state(:ready)
    end
  end

  # == Class Methods ========================================================
  
  # == Instance Methods =====================================================

end
