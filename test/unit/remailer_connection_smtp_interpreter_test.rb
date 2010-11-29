require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class Receiver
  attr_accessor :options
  
  def self.encode_authentication(username, password)
    Remailer::Connection.encode_authentication(username, password)
  end
  
  def initialize(options = { })
    @sent = [ ]
    @options = options
  end
  
  def hostname
    'localhost.local'
  end
  
  def requires_authentication?
    !!@options[:username]
  end
  
  def use_tls?
    !!@options[:use_tls]
  end
  
  def send_line(data)
    @sent << data
  end
  
  def start_tls
    @started_tls = true
  end
  
  def started_tls?
    !!@started_tls
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
end

class RemailerConnectionSmtpInterpreterTest < Test::Unit::TestCase
  def test_defaults
    interpreter = Remailer::Connection::SmtpInterpreter.new
    
    assert_equal :initialized, interpreter.state
  end
  
  def test_receiver_default_state
    receiver = Receiver.new

    assert_equal false, receiver.closed?
    assert_equal nil, receiver.read
  end

  def test_receiver_options
    receiver = Receiver.new(:use_tls => true)

    assert_equal true, receiver.use_tls?
    assert_equal false, receiver.requires_authentication?

    receiver = Receiver.new(:username => 'test@example.com', :password => 'tester')

    assert_equal false, receiver.use_tls?
    assert_equal true, receiver.requires_authentication?
  end
  
  def test_standard_connection
    receiver = Receiver.new
    interpreter = Remailer::Connection::SmtpInterpreter.new(:delegate => receiver)

    assert_equal :initialized, interpreter.state
    
    interpreter.interpret(220, "mail.postageapp.com ESMTP Exim 4.63")

    assert_equal :ehlo, interpreter.state
    assert_equal 'EHLO localhost.local', receiver.read

    interpreter.interpret(250, "mail.postageapp.com Hello", true)
    assert_equal :ehlo, interpreter.state

    interpreter.interpret(250, "SIZE 52428800", true)
    assert_equal :ehlo, interpreter.state

    interpreter.interpret(250, "PIPELINING", true)
    assert_equal :ehlo, interpreter.state

    interpreter.interpret(250, "STARTTLS", true)
    assert_equal :ehlo, interpreter.state

    interpreter.interpret(250, "HELP")
    assert_equal :ready, interpreter.state
    
    interpreter.enter_state(:quit)

    assert_equal :quit, interpreter.state
    assert_equal 'QUIT', receiver.read
    
    interpreter.interpret(221, 'mail.postageapp.com closing connection')
    assert_equal true, receiver.closed?
  end

  def test_tls_connection_with_support
    receiver = Receiver.new(:use_tls => true)
    interpreter = Remailer::Connection::SmtpInterpreter.new(:delegate => receiver)

    interpreter.interpret(220, "mail.postageapp.com ESMTP Exim 4.63")
    assert_equal 'EHLO localhost.local', receiver.read
    
    interpreter.interpret(250, "mail.postageapp.com Hello", true)
    interpreter.interpret(250, "RANDOMCOMMAND", true)
    interpreter.interpret(250, "EXAMPLECOMMAND", true)
    interpreter.interpret(250, "SIZE 52428800", true)
    interpreter.interpret(250, "PIPELINING", true)
    interpreter.interpret(250, "STARTTLS", true)
    interpreter.interpret(250, "HELP")
    
    assert_equal :starttls, interpreter.state
    assert_equal 'STARTTLS', receiver.read
    assert_equal false, receiver.started_tls?
    
    interpreter.interpret(220, "TLS go ahead")
    assert_equal true, receiver.started_tls?
    
    assert_equal :ready, interpreter.state
  end

  def test_tls_connection_without_support
    receiver = Receiver.new(:use_tls => true)
    interpreter = Remailer::Connection::SmtpInterpreter.new(:delegate => receiver)

    interpreter.interpret(220, "mail.postageapp.com ESMTP Exim 4.63")
    assert_equal 'EHLO localhost.local', receiver.read
    
    interpreter.interpret(250, "mail.postageapp.com Hello", true)
    interpreter.interpret(250, "HELP")
    
    assert_equal false, receiver.started_tls?

    assert_equal :ready, interpreter.state
  end

  def test_basic_plaintext_auth_accepted
    receiver = Receiver.new(:username => 'tester@example.com', :password => 'tester')
    interpreter = Remailer::Connection::SmtpInterpreter.new(:delegate => receiver)

    interpreter.interpret(220, "mail.postageapp.com ESMTP Exim 4.63")
    assert_equal 'EHLO localhost.local', receiver.read
    
    interpreter.interpret(250, "mail.postageapp.com Hello", true)
    interpreter.interpret(250, "HELP")
    
    assert_equal false, receiver.started_tls?

    assert_equal :auth, interpreter.state
    assert_equal "AUTH PLAIN AHRlc3RlckBleGFtcGxlLmNvbQB0ZXN0ZXI=", receiver.read
    
    interpreter.interpret(235, 'Accepted')
    
    assert_equal :ready, interpreter.state
  end

  def test_basic_plaintext_auth_rejected
    receiver = Receiver.new(:username => 'tester@example.com', :password => 'tester')
    interpreter = Remailer::Connection::SmtpInterpreter.new(:delegate => receiver)

    interpreter.interpret(220, "mail.postageapp.com ESMTP Exim 4.63")
    assert_equal 'EHLO localhost.local', receiver.read
    
    interpreter.interpret(250, "mail.postageapp.com Hello", true)
    interpreter.interpret(250, "HELP")
    
    assert_equal false, receiver.started_tls?

    assert_equal :auth, interpreter.state
    assert_equal "AUTH PLAIN AHRlc3RlckBleGFtcGxlLmNvbQB0ZXN0ZXI=", receiver.read
    
    interpreter.interpret(235, 'Accepted')
    
    assert_equal :ready, interpreter.state
  end
end
