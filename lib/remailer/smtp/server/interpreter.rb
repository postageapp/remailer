class Remailer::SMTP::Server::Interpreter < Remailer::Interpreter
  # == State Definitions ====================================================

  default do |error|
    delegate.send_line("500 Invalid command")
  end
  
  state :initialized do
    enter do
      self.send_banner
      
      enter_state(:reset)
    end
  end
  
  state :reset do
    enter do
      self.reset_transaction!
      
      enter_state(:ready)
    end
  end
  
  state :ready do
    interpret(/^\s*EHLO\s+(\S+)\s*$/) do |remote_host|
      delegate.validate_hostname(remote_host) do |valid|
        if (valid)
          delegate.log(:debug, "#{delegate.remote_ip}:#{delegate.remote_port} to #{delegate.local_ip}:#{delegate.local_port} Accepting connection from #{remote_host}")
          @remote_host = remote_host

          delegate.send_line("250-#{delegate.server_name} Hello #{delegate.remote_host} [#{delegate.remote_ip}]")
          delegate.send_line("250-AUTH PLAIN")
          delegate.send_line("250-SIZE 35651584")
          delegate.send_line("250-STARTTLS") if (delegate.tls?)
          delegate.send_line("250 OK")
        else
          delegate.log(:debug, "#{delegate.remote_ip}:#{delegate.remote_port} to #{delegate.local_ip}:#{delegate.local_port} Rejecting connection from #{remote_host} because of invalid FQDN")
          delegate.send_line("504 Need fully qualified hostname")
        end
      end
    end

    interpret(/^\s*HELO\s+(\S+)\s*$/) do |remote_host|
      delegate.validate_hostname(remote_host) do |valid|
        if (valid)
          delegate.log(:debug, "#{delegate.remote_ip}:#{delegate.remote_port} to #{delegate.local_ip}:#{delegate.local_port} Accepting connection from #{remote_host}")
          @remote_host = remote_host

          delegate.send_line("250 #{delegate.server_name} Hello #{delegate.remote_host} [#{delegate.remote_ip}]")
        else
          delegate.log(:debug, "#{delegate.remote_ip}:#{delegate.remote_port} to #{delegate.local_ip}:#{delegate.local_port} Rejecting connection from #{remote_host} because of invalid FQDN")
          delegate.send_line("504 Need fully qualified hostname")
        end
      end
    end
    
    interpret(/^\s*MAIL\s+FROM:\s*<([^>]+)>\s*/) do |address|
      if (Remailer::EmailAddress.valid?(address))
        accept, message = will_accept_sender(address)

        if (accept)
          @transaction.sender = address
        end

        delegate.send_line(message)
      else
        delegate.send_line("501 Email address is not RFC compliant")
      end
    end

    interpret(/^\s*RCPT\s+TO:\s*<([^>]+)>\s*/) do |address|
      if (@transaction.sender)
        if (Remailer::EmailAddress.valid?(address))
          accept, message = will_accept_recipient(address)

          if (accept)
            @transaction.recipients ||= [ ]
            @transaction.recipients << address
          end

          delegate.send_line(message)
        else
          delegate.send_line("501 Email address is not RFC compliant")
        end
      else
        delegate.send_line("503 Sender not specified")
      end
    end
    
    interpret(/^\s*AUTH\s+PLAIN\s+(.*)\s*$/) do |auth|
      # 235 2.7.0 Authentication successful
      delegate.send("235 whatever")
    end

    interpret(/^\s*AUTH\s+PLAIN\s*$/) do
      # Multi-line authentication method
      enter_state(:auth_plain)
    end
    
    interpret(/^\s*STARTTLS\s*$/) do
      if (@tls_started)
        delegate.send_line("454 TLS already started")
      elsif (delegate.tls?)
        delegate.send_line("220 TLS ready to start")
        delegate.start_tls(
          private_key_file: Remailer::SMTP::Server.private_key_path,
          cert_chain_file: Remailer::SMTP::Server.ssl_cert_path
        )
        
        @tls_started = true
      else
        delegate.send_line("421 TLS not supported")
      end
    end
    
    interpret(/^\s*DATA\s*$/) do
      if (@transaction.sender)
      else
        delegate.send_line("503 valid RCPT command must precede DATA")
      end
      
      enter_state(:data)
      delegate.send_line("354 Supply message data")
    end

    interpret(/^\s*NOOP\s*$/) do |remote_host|
      delegate.send_line("250 OK")
    end

    interpret(/^\s*RSET\s*$/) do |remote_host|
      delegate.send_line("250 Reset OK")
      
      enter_state(:reset)
    end
    
    interpret(/^\s*QUIT\s*$/) do
      delegate.send_line("221 #{delegate.server_name} closing connection")

      delegate.close_connection(true)
    end
  end
  
  state :data do
    interpret(/^\.$/) do
      accept, message = will_accept_transaction(@transaction)
      
      if (accept)
        accept, message = delegate.receive_transaction(@transaction)
        
        delegate.send_line(message)
      else
        delegate.send_line(message)
      end

      self.reset_transaction!

      enter_state(:ready)
    end
    
    default do |line|
      # RFC5321 4.5.2 - Leading dot is removed if line has content

      @transaction.data << (line.sub(/^\./, '') << Remailer::Constants::CRLF)
    end
  end
  
  state :auth_plain do
    # Receive a single line of authentication
    # ...
  end
  
  state :reply do
    enter do
      # Random delay if required
      delegate.send_line(@reply)
    end
    
    default do
      delegate.send_line("554 SMTP Synchronization Error")
      enter_state(:ready)
    end
  end

  state :timeout do
    enter do
      delegate.send_line("420 Idle connection closed")

      delegate.close_connection(true)
    end
  end

  # == Instance Methods =====================================================

  def reset_transaction!
    @transaction = Remailer::SMTP::Server::Transaction.new
  end

  def send_banner
    delegate.send_line("220 #{delegate.server_name} Remailer ESMTP Server Ready")
  end

  def reset_ttl!
    @timeout_at = Time.now + self.connection_ttl
  end

  def enter_state(state)
    self.reset_ttl!
    
    super(state)
  end

  def connection_ttl
    10
  end
  
  def ttl_expired?
    @timeout_at ? (Time.now > @timeout_at) : false
  end
  
  def check_for_timeout!
    if (self.ttl_expired?)
      enter_state(:timeout)
    end
  end
  
  def will_accept_sender(sender)
    [ true, "250 Accepted" ]
  end
  
  def will_accept_recipient(recipient)
    [ true, "250 Accepted" ]
  end
  
  def will_accept_transaction(transaction)
    [ true, "250 Accepted" ]
  end
end
