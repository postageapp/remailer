class Remailer::SOCKS5::Client::Interpreter < Remailer::Interpreter
  # == Constants ============================================================

  # RFC1928 and RFC1929 define these values
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
  
  # == State Mapping ========================================================

  state :initialized do
    enter do
      proxy_options = delegate.options[:proxy]

      socks_methods = [ ]
      
      if (proxy_options[:username])
        socks_methods << SOCKS5_METHOD[:username_password]
      end
      
      proxy_options[:port] ||= Remailer::Constants::SOCKS5_PORT

      delegate.debug_notification(:proxy, "Initiating proxy connection through #{proxy_options[:host]}:#{proxy_options[:port]}")

      delegate.send_data(
        [
          SOCKS5_VERSION,
          socks_methods.length,
          socks_methods
        ].flatten.pack('CCC*')
      )
    end
    
    parse do |s|
      if (s.length >= 2)
        version, method = s.slice!(0,2).unpack('CC')
      
        method
      end
    end
    
    interpret(SOCKS5_METHOD[:username_password]) do
      enter_state(:authentication)
    end
    
    default do
      enter_state(:resolving_destination)
    end
  end
  
  state :resolving_destination do
    enter do
      delegate.resolve_hostname(delegate.options[:host]) do |address|
        @destination_address = address
        enter_state(:connect_through_proxy)
      end
    end
  end
  
  state :connect_through_proxy do
    enter do
      delegate.proxy_connection_initiated!
      
      if (@destination_address)
        delegate.debug_notification(:proxy, "Sending proxy connection request to #{@destination_address.unpack('CCCC').join('.')}:#{delegate.options[:port]}")

        delegate.send_data(
          [
            SOCKS5_VERSION,
            SOCKS5_COMMAND[:connect],
            0,
            SOCKS5_ADDRESS_TYPE[:ipv4],
            @destination_address,
            delegate.options[:port]
          ].pack('CCCCA4n')
        )
      else
        @error_message = "Could not resolve hostname #{delegate.options[:host]}"
        enter_state(:failed)
      end
    end
    
    parse do |s|
      if (s.length >= 10)
        version, reply, reserved, address_type, address, port = s.slice!(0,10).unpack('CCCCNn')
      
        [
          reply,
          {
            :address => address,
            :port => port,
            :address_type => address_type
          }
        ]
      end
    end
  
    interpret(0) do
      enter_state(:connected)
    end
    
    default do |reply|
      @reply = reply
      enter_state(:failed)
    end
  end
  
  state :authentication do
    enter do
      delegate.debug_notification(:proxy, "Sending proxy authentication")

      proxy_options = delegate.options[:proxy]
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
    end
    
    parse do |s|
    end
    
    interpret(0) do
      enter_state(:connected)
    end
  end
  
  state :connected do
    enter do
      delegate_call(:after_proxy_connected)
    end
  end
  
  state :failed do
    enter do
      if (@error_message)
        delegate.debug_notification(:error, @error_message)
        delegate.error_notification("SOCKS5", @error_message)
      else
        message = "Proxy server returned error code #{@reply}: #{SOCKS5_REPLY[@reply]}"
        delegate.debug_notification(:error, message)
        delegate.error_notification("SOCKS5_#{@reply}", message)
      end
      delegate.connect_notification(false, message)
      delegate.close_connection
    end
    
    terminate
  end

  # == Class Methods ========================================================

  # == Instance Methods =====================================================
  
  def label
    'SOCKS5'
  end
end
