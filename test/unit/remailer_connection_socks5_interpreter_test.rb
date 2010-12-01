require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class Socks5Delegate
  attr_reader :options
  
  def initialize(options = nil)
    @sent = [ ]
    @options = (options or { })
  end
  
  def resolve_hostname(hostname)
    record = Socket.gethostbyname(hostname)
    
    record and record.last
  end
  
  def hostname
    'localhost.local'
  end

  def send_data(data)
    @sent << data
  end

  def close_connection
    @closed = true
  end
  
  def closed?
    !!@closed
  end
  
  def clear!
    @sent = [ ]
  end
  
  def size
    @sent.size
  end
  
  def read
    @sent.shift
  end

  def method_missing(*args)
  end
end

class RemailerConnectionSocks5InterpreterTest < Test::Unit::TestCase
  def test_defaults
    delegate = Socks5Delegate.new(
      :proxy => {
        :host => 'example.net'
      }
    )
    interpreter = Remailer::Connection::Socks5Interpreter.new(:delegate => delegate)
    
    assert_equal :connect_to_proxy, interpreter.state
    assert_equal false, delegate.closed?
  end
  
  def test_simple_connection
    delegate = Socks5Delegate.new(
      :host => '1.2.3.4',
      :port => 4321,
      :proxy => {
        :host => 'example.net'
      }
    )
    interpreter = Remailer::Connection::Socks5Interpreter.new(:delegate => delegate)
    
    assert_equal :connect_to_proxy, interpreter.state
    assert_equal false, delegate.closed?
    
    sent = delegate.read
    
    assert_equal 2, sent.length
    
    assert_equal [ Remailer::Connection::Socks5Interpreter::SOCKS5_VERSION, 0 ], sent.unpack('CC')
    
    reply = [
      Remailer::Connection::Socks5Interpreter::SOCKS5_VERSION,
      Remailer::Connection::Socks5Interpreter::SOCKS5_METHOD[:no_auth]
    ].pack('CC')
    
    interpreter.process(reply)
    
    assert_equal false, interpreter.error?
    assert_equal :connect_through_proxy, interpreter.state
    assert_equal '', reply
    
    sent = delegate.read

    assert_equal 10, sent.length
    
    assert_equal [
      Remailer::Connection::Socks5Interpreter::SOCKS5_VERSION,
      Remailer::Connection::Socks5Interpreter::SOCKS5_COMMAND[:connect],
      0,
      Remailer::Connection::Socks5Interpreter::SOCKS5_ADDRESS_TYPE[:ipv4],
      [ 1, 2, 3, 4 ].pack('CCCC'),
      4321
    ], sent.unpack('CCCCA4n')

    interpreter.process([
      Remailer::Connection::Socks5Interpreter::SOCKS5_VERSION,
      0, # No error
      0,
      Remailer::Connection::Socks5Interpreter::SOCKS5_ADDRESS_TYPE[:ipv4],
      [ 1, 2, 3, 4 ].pack('CCCC'),
      4321
    ].pack('CCCCA4n'))
    
    assert_equal :connected, interpreter.state
  end
end
