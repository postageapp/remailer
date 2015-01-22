require_relative '../helper'

class SOCKS5Delegate
  attr_reader :options
  
  def initialize(options = nil)
    @sent = [ ]
    @options = (options or { })
  end
  
  def resolve_hostname(hostname)
    record = Socket.gethostbyname(hostname)
    
    resolved = (record and record.last)
    
    if (block_given?)
      yield(resolved)
    end
    
    resolved
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

class RemailerSOCKS5ClientInterpreterTest < MiniTest::Test
  def test_defaults
    delegate = SOCKS5Delegate.new(
      proxy: {
        host: 'example.net'
      }
    )

    interpreter = Remailer::SOCKS5::Client::Interpreter.new(delegate: delegate)
    
    assert_equal :initialized, interpreter.state
    assert_equal false, delegate.closed?
  end
  
  def test_simple_connection
    delegate = SOCKS5Delegate.new(
      host: '1.2.3.4',
      port: 4321,
      proxy: {
        host: 'example.net'
      }
    )
    interpreter = Remailer::SOCKS5::Client::Interpreter.new(delegate: delegate)
    
    assert_equal :initialized, interpreter.state
    assert_equal false, delegate.closed?
    
    sent = delegate.read
    
    assert_equal 2, sent.length
    
    assert_equal [ Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION, 0 ], sent.unpack('CC')
    
    reply = [
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_METHOD[:no_auth]
    ].pack('CC')
    
    interpreter.process(reply)
    
    assert_equal false, interpreter.error?
    assert_equal :connect_through_proxy, interpreter.state
    assert_equal '', reply
    
    sent = delegate.read

    assert sent, "No data received"
    assert_equal 10, sent.length
    
    assert_equal [
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_COMMAND[:connect],
      0,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_ADDRESS_TYPE[:ipv4],
      [ 1, 2, 3, 4 ].pack('CCCC'),
      4321
    ], sent.unpack('CCCCA4n')

    interpreter.process([
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION,
      0, # No error
      0,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_ADDRESS_TYPE[:ipv4],
      [ 1, 2, 3, 4 ].pack('CCCC'),
      4321
    ].pack('CCCCA4n'))
    
    assert_equal :connected, interpreter.state
  end

  def test_combined_socks5_smtp
    delegate = SOCKS5Delegate.new(
      host: '1.2.3.4',
      port: 4321,
      proxy: {
        host: 'example.net'
      }
    )
    interpreter = Remailer::SOCKS5::Client::Interpreter.new(delegate: delegate)
    
    assert_equal :initialized, interpreter.state
    assert_equal false, delegate.closed?
    
    sent = delegate.read
    
    assert_equal 2, sent.length
    
    assert_equal [ Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION, 0 ], sent.unpack('CC')
    
    reply = [
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_METHOD[:no_auth]
    ].pack('CC')
    
    interpreter.process(reply)
    
    assert_equal false, interpreter.error?
    assert_equal :connect_through_proxy, interpreter.state
    assert_equal '', reply
    
    sent = delegate.read

    assert sent, "No data received"
    assert_equal 10, sent.length
    
    assert_equal [
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_COMMAND[:connect],
      0,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_ADDRESS_TYPE[:ipv4],
      [ 1, 2, 3, 4 ].pack('CCCC'),
      4321
    ], sent.unpack('CCCCA4n')

    buffer = [
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_VERSION,
      0, # No error
      0,
      Remailer::SOCKS5::Client::Interpreter::SOCKS5_ADDRESS_TYPE[:ipv4],
      [ 1, 2, 3, 4 ].pack('CCCC'),
      4321
    ].pack('CCCCA4n') + '421 Welcome to an ESTMP Server'

    interpreter.process(buffer)

    assert_equal '421 Welcome to an ESTMP Server', buffer
    
    assert_equal :connected, interpreter.state
  end
end
