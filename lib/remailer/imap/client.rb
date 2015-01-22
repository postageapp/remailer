class Remailer::IMAP::Client < Remailer::AbstractConnection
  # == Exceptions ===========================================================
  
  # == Extensions ===========================================================
  
  include Remailer::Support
  
  # == Submodules ===========================================================
  
  autoload(:Interpreter, 'remailer/imap/client/interpreter')

  # == Constants ============================================================
  
  DEFAUT_TIMEOUT = 60
  
  # == Properties ===========================================================

  # == Class Methods ========================================================
  
  def self.default_timeout
    DEFAULT_TIMEOUT
  end

  def self.default_port
    IMAPS_PORT
  end

  # Opens a connection to a specific IMAP server. Options can be specified:
  # * port => Numerical port number (default is 993)
  # * require_tls => If true will fail connections to non-TLS capable
  #   servers (default is false)
  # * username => Username to authenticate with the IMAP server
  # * password => Password to authenticate with the IMAP server
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
  def self.open(imap_server, options = nil, &block)
    super(imap_server, options, &block)
  end
  
  # == Instance Methods =====================================================
  
  def after_initialize
    if (using_proxy?)
      @connecting_to_proxy = true
      use_socks5_interpreter!
    else
      if (@options[:use_tls])
        self.start_tls
      end
      
      use_imap_interpreter!
    end
    
    @command_tags = { }
    @issued_command = { }
  end

  # Callback receiver for when the proxy connection has been completed.
  def after_proxy_connected
    if (@options[:use_tls])
      self.start_tls
    end
    
    use_imap_interpreter!
  end
  
  def after_unbind
    debug_notification(:disconnect, "Disconnected by remote.")
    
    @command_tags.each do |tag, callback|
      callback[1].call(nil)
    end
  end

  def receive_response(tag, status, message, additional = nil)
    if (set = @command_tags.delete(tag))
      @issued_command.delete(set[0])
      set[1].call(status, message, additional)
    end
  end
  
  # -- Commands -------------------------------------------------------------
  
  def capability
    self.issue_command('CAPABILITY') do |status, message, additional|
      yield(additional)
    end
  end
  
  def login(username, password)
    self.issue_command('LOGIN', quoted(username), quoted(password)) do |status, message, additional|
      yield(status, message, additional)
    end
  end
  
  def list(reference_name = '/', mailbox_name = '*')
    self.issue_command('LIST', quoted(reference_name), quoted(mailbox_name)) do |status, message, additional|
      yield(status, message, additional)
    end
  end

  def select(mailbox_name = 'INBOX')
    self.issue_command('SELECT', quoted(mailbox_name)) do |status, message, additional|
      yield(status, message, additional)
    end
  end

  def examine(mailbox_name = 'INBOX')
    self.issue_command('EXAMINE', quoted(mailbox_name)) do |status, message, additional|
      yield(status, message, additional)
    end
  end

  def status(mailbox_name = 'INBOX', *flags)
    flags.flatten!
    flags = [ :uidnext, :messages ] if (flags.empty?)
    
    # Valid flags are: MESSAGES RECENT UIDNEXT UIDVALIDITY UNSEEN
    
    self.issue_command('STATUS', quoted(mailbox_name), "(#{flags.collect { |f| f.to_s.upcase }.join(' ')})") do |status, message, additional|
      yield(status, message, additional)
    end
  end
  
  def noop
    self.issue_command('NOOP') do |status, message, additional|
      yield(status, message, additional)
    end
  end
  
  def fetch(range, *options)
    fetch_options = { }
    
    options.each do |option|
      case (option)
      when Hash
        fetch_options.merge(option)
      else
        fetch_options[option] = true
      end
    end
    
    if (fetch_options.empty?)
      fetch_options[:all] = true
    end
    
    sequence_set =
      case (range)
      when Range
        "#{range.min}:#{range.max}"
      else
        range.to_s
      end
      
    items =
      if (fetch_options[:all])
        'ALL'
      elsif (fetch_options[:fast])
        'FAST'
      elsif (fetch_options[:full])
        'FULL'
      elsif (body_options = fetch_options[:body])
        case (body_options)
        when Hash
          # ...
        else
          'BODY'
        end
      end
    
    self.issue_command('FETCH', sequence_set, items) do |status, message, additional|
      yield(status, message, additional)
    end
  end
  
  def idle
    self.issue_command('IDLE') do |status, message, additional|
      yield(status, message, additional)
    end
    
    lambda { self.send_line('DONE') }
  end

protected
  # Switches to use the IMAP interpreter for all subsequent communication
  def use_imap_interpreter!
    @interpreter = Interpreter.new(delegate: self)
  end

  def next_tag
    @next_tag ||= (rand(1 << 32) << 32) | (1 << 64)
  
    @next_tag += 1
  
    @next_tag.to_s(16)
  end

  def issue_command(*args, &block)
    tag = self.next_tag
  
    self.send_line(([ tag ] + args.flatten).join(' '))
  
    @command_tags[tag] = [ args.first, block ]
    @issued_command[args.first] = [ tag, block ]
  
    tag
  end

  def pending_command_with_tag(tag)
    set = @command_tags[tag]
  
    set and set[0] or false
  end

  def pending_command_of_type(type)
    set = @issued_command[tag]
  
    set and set[0] or false
  end
end
