require 'socket'
require 'eventmachine'

class Remailer::SMTP::Server < EventMachine::Protocols::LineAndTextProtocol
  # == Submodules ===========================================================
  
  autoload(:Interpreter, 'remailer/smtp/server/interpreter')

  # == Constants ============================================================
  
  PERSONALITIES = [
    :gmail_mx, :yahoo_mx, :hotmail_mx, :aol_mx,
    :sendmail_mx, :postfix_mx, :exim_mx, :qmail_mx,
    :gmail_auth, :sendmail_auth, :postfix_auth, :exim_auth, :qmail_auth,
    :exchange_auth
  ].freeze
  
  QUIRKS = [
    :not_an_smtp_server,
    :not_authorized,
    :no_header,
    :timeout_during_data,
    :random_timeout,
    :disconnect_during_data,
    :reject_data,
    :rate_limit
  ].freeze

  # == Properties ===========================================================
  
  attr_reader :server_name, :quirks
  attr_reader :remote_ip, :remote_port
  attr_reader :local_ip, :local_port
  attr_reader :local_config
  
  # == Class Methods ========================================================
  
  def self.connections
    @connections ||= { }
  end
  
  def self.connection_servers
    self.connections.keys
  end

  def self.connection_pools
    @connection_pools ||= { }
  end
  
  def self.connection_pool_count(pool)
    pool_set = self.connection_pools[pool]
    
    pool_set ? pool_set.length : 0
  end
  
  def self.accepted_connection(server, pool, remote)
    self.connections[server] = true
    (self.connection_pools[pool] ||= [ ]) << remote
  end
  
  def self.closed_connection(server, pool, remote)
    self.connections.delete(server)

    if (pool_set = self.connection_pools[pool])
      pool_set.delete(remote)
    end
  end

  def self.connections_for(pool)
    self.connection_pools[pool] ||= [ ]
  end

  # == Instance Methods =====================================================
  
  def initialize(server_name = nil, personality = nil, quirks = nil)
    super

    @remote_port, @remote_ip = Socket.unpack_sockaddr_in(get_peername)
    @local_port, @local_ip = Socket.unpack_sockaddr_in(get_sockname)
    
    @local_config = Birdbrain.hosts[@local_ip] || { }
    
    @server_name = server_name || @local_config[:hostname] || Birdbrain.hostname(@local_ip) || @local_ip
    @quirks = quirks || { }

    @persona = (personality || @local_config[:persona] || Birdbrain::Persona)

    Birdbrain.engine.logger.debug("Connection from #{@remote_ip}:#{@remote_port} to #{@local_ip}:#{@local_port} using #{@persona}")
  end
  
  def accepted_connection(pool)
    self.class.accepted_connection(self, pool, "#{@remote_ip}:#{@remote_port}")
  end
  
  def closed_connection(pool)
    self.class.closed_connection(self, pool, "#{@remote_ip}:#{@remote_port}")
  end
  
  def post_init
    super
    
    puts "<OPEN>" if (DEBUGGING)
    
    self.resolve_remote_host!

    @interpreter = @persona.new(:delegate => self)
    
    @local_config.each do |key, value|
      case (key)
      when :hostname, :persona
        # Ignore, already applied
      else
        mutator = :"#{key}="

        if (@interpreter.respond_to?(mutator))
          @interpreter.send(mutator, value)
        else
          raise "#{@interpreter.class} does not allow configuring of `#{key}`"
        end
      end
    end
  end
  
  def receive_line(line)
    puts "-> #{line.inspect}" if (DEBUGGING)
    
    @interpreter.process(line)

  rescue Object => e
    STDERR.puts("#{e.class}: #{e}")
  end
  
  def unbind
    super
    
    Birdbrain.engine.logger.debug("Connection from #{@remote_ip} to #{@local_ip} closed")
  
    self.closed_connection(@interpreter.pool)
  
    puts "<CLOSED>" if (DEBUGGING)
  end
  
  def send_line(line)
    puts "<- #{line}" if (DEBUGGING)
    send_data(line + CRLF)
  end
  
  def tls?
    ENV['TLS']
  end
  
  def remote_host
    @remote_host
  end
  
  def resolve_remote_host!
    Birdbrain.hostname_for_ip(@remote_ip) do |hostname|
      @remote_host = hostname

      yield(hostname) if (block_given?)
    end
  end
  
  def receive_message(email, accepted = true)
    error = nil
    unique_id = nil
    
    accepted_label = accepted ? 'accepted' : 'rejected'
    
    begin
      parsed = email.parsed
      
      unique_id = parsed.message_id
    rescue => e
      error = "[#{e.class}] #{e}"
    end
    
    unique_id ||= 'unknown'
    
    email.recipients.each do |recipient|
      Birdbrain.engine.logger.debug("Email <#{unique_id}> from #{email.sender} to #{recipient} was #{accepted_label}#{error ? " (#{error})" : ''}")
      
      Birdbrain.engine.log_receipt!(
        unique_id,
        email.sender,
        recipient,
        [ @remote_ip, @remote_port ].join(':'),
        [ @local_ip, @local_port ].join(':'),
        accepted_label,
        error
      )
    end
    
    puts "=> #{email.class} received from #{email.sender} to #{email.recipients.join(', ')}" if (DEBUGGING)
  end
  
  def validate_hostname(hostname)
    Birdbrain.resolver.resolve(hostname, :a) do |answers|
      if (answers and !answers.empty?)
        # FIX: Make a more rigorous check here
        
        yield(true)
      else
        yield(false)
      end
    end
  end
  
  def check_for_timeout!
    @interpreter.check_for_timeout!
  end
end
