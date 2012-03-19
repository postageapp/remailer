require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class SMTPDelegate
  attr_accessor :options, :protocol, :active_message
  attr_accessor :tls_support
  
  def initialize(options = { })
    @sent = [ ]
    @options = options
    @protocol = :smtp
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
  
  def send_line(data  = '')
    @sent << data
  end
  
  def start_tls
    @started_tls = true
  end
  
  def started_tls?
    !!@started_tls
  end
  
  def tls_support?
    !!@tls_support
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

class RemailerSMTPClientInterpreterTest < Test::Unit::TestCase
  def test_split_reply
    assert_mapping(
      '250 OK' => [ 250, 'OK' ],
      '250 Long message' => [ 250, 'Long message' ],
      'OK' => nil,
      '100-Example' => [ 100, 'Example', :continued ]
    ) do |reply|
      Remailer::SMTP::Client::Interpreter.split_reply(reply)
    end
  end

  def test_parser
    interpreter = Remailer::SMTP::Client::Interpreter.new
    
    assert_mapping(
      "250 OK\r\n" => [ 250, 'OK' ],
      "250 Long message\r\n" => [ 250, 'Long message' ],
      "OK\r\n" => nil,
      "100-Example\r\n" => [ 100, 'Example', :continued ],
      "100-Example" => nil
    ) do |reply|
      interpreter.parse(reply.dup)
    end
  end

  def test_encode_data
    sample_data = "Line 1\r\nLine 2\r\n.\r\nLine 3\r\n.Line 4\r\n"
    
    assert_equal "Line 1\r\nLine 2\r\n..\r\nLine 3\r\n..Line 4\r\n", Remailer::SMTP::Client::Interpreter.encode_data(sample_data)
  end
  
  def test_base64
    assert_mapping(
      'example' => 'example',
      "\x7F" => "\x7F",
      nil => ''
    ) do |example|
      Remailer::SMTP::Client::Interpreter.base64(example).unpack('m')[0]
    end
  end
  
  def test_encode_authentication
    assert_mapping(
      %w[ tester tester ] => 'AHRlc3RlcgB0ZXN0ZXI='
    ) do |username, password|
      Remailer::SMTP::Client::Interpreter.encode_authentication(username, password)
    end
  end

  def test_defaults
    interpreter = Remailer::SMTP::Client::Interpreter.new
    
    assert_equal :initialized, interpreter.state
  end
  
  def test_delegate_default_state
    delegate = SMTPDelegate.new

    assert_equal false, delegate.closed?
    assert_equal nil, delegate.read
    assert_equal 0, delegate.size
  end

  def test_delegate_options
    delegate = SMTPDelegate.new(:use_tls => true)

    assert_equal true, delegate.use_tls?
    assert_equal false, delegate.requires_authentication?

    delegate = SMTPDelegate.new(:username => 'test@example.com', :password => 'tester')

    assert_equal false, delegate.use_tls?
    assert_equal true, delegate.requires_authentication?
  end

  def test_standard_smtp_connection
    delegate = SMTPDelegate.new
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    assert_equal :initialized, interpreter.state
    
    interpreter.process("220 mail.example.com SMTP Example\r\n")

    assert_equal :helo, interpreter.state
    assert_equal 'HELO localhost.local', delegate.read

    interpreter.process("250 mail.example.com Hello\r\n")
    assert_equal :ready, interpreter.state

    interpreter.enter_state(:quit)

    assert_equal :quit, interpreter.state
    assert_equal 'QUIT', delegate.read
    
    interpreter.process("221 mail.example.com closing connection\r\n")
    assert_equal true, delegate.closed?
  end

  def test_standard_smtp_connection_send_email
    delegate = SMTPDelegate.new
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    assert_equal :initialized, interpreter.state
    
    interpreter.process("220 mail.example.com SMTP Example\r\n")

    assert_equal :helo, interpreter.state
    assert_equal 'HELO localhost.local', delegate.read

    interpreter.process("250 mail.example.com Hello\r\n")
    assert_equal :ready, interpreter.state

    interpreter.enter_state(:quit)

    assert_equal :quit, interpreter.state
    assert_equal 'QUIT', delegate.read
    
    interpreter.process("221 mail.example.com closing connection\r\n")
    assert_equal true, delegate.closed?
    
    delegate.active_message = {
      :from => 'from@example.com',
      :to => 'to@example.com',
      :data => "Subject: Test Message\r\n\r\nThis is a message!\r\n"
    }
    
    interpreter.enter_state(:send)
    
    assert_equal :mail_from, interpreter.state
    
    assert_equal 'MAIL FROM:<from@example.com>', delegate.read
    
    interpreter.process("250 OK\r\n")
    
    assert_equal :rcpt_to, interpreter.state

    assert_equal 'RCPT TO:<to@example.com>', delegate.read
    
    interpreter.process("250 Accepted\r\n")
    
    assert_equal :data, interpreter.state
    
    assert_equal 'DATA', delegate.read

    interpreter.process("354 Enter message, ending with \".\" on a line by itself\r\n")
    
    assert_equal :sending, interpreter.state
    
    interpreter.process("250 OK id=1PN95Q-00072L-Uw\r\n")
    
    assert_equal :ready, interpreter.state
  end
  
  def test_standard_esmtp_connection
    delegate = SMTPDelegate.new
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    assert_equal :initialized, interpreter.state
    
    interpreter.process("220 mail.example.com ESMTP Exim 4.63\r\n")

    assert_equal :ehlo, interpreter.state
    assert_equal 'EHLO localhost.local', delegate.read

    interpreter.process("250-mail.example.com Hello\r\n")
    assert_equal :ehlo, interpreter.state

    interpreter.process("250-SIZE 52428800\r\n")
    assert_equal :ehlo, interpreter.state

    interpreter.process("250-PIPELINING\r\n")
    assert_equal :ehlo, interpreter.state

    interpreter.process("250-STARTTLS\r\n")
    assert_equal :ehlo, interpreter.state

    interpreter.process("250 HELP\r\n")
    assert_equal :ready, interpreter.state
    
    interpreter.enter_state(:quit)

    assert_equal :quit, interpreter.state
    assert_equal 'QUIT', delegate.read
    
    interpreter.process("221 mail.example.com closing connection\r\n")

    assert_equal :terminated, interpreter.state
    assert_equal true, delegate.closed?
  end
  
  def test_multi_line_hello_response
    delegate = SMTPDelegate.new(:use_tls => true)
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    assert_equal :initialized, interpreter.state
    assert_equal :smtp, delegate.protocol

    interpreter.process("220-mail.example.com Hello ESMTP Example Server\r\n")
    assert_equal :initialized, interpreter.state
    assert_equal :esmtp, delegate.protocol

    interpreter.process("220-This is a long notice that is posted here\r\n")
    assert_equal :initialized, interpreter.state

    interpreter.process("220-as some servers like to have a little chat\r\n")
    assert_equal :initialized, interpreter.state

    interpreter.process("220 with you before getting down to business.\r\n")

    assert_equal :ehlo, interpreter.state
  end

  def test_tls_connection_with_support
    delegate = SMTPDelegate.new(:use_tls => true)
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)
    
    assert_equal true, delegate.use_tls?
    assert_equal :initialized, interpreter.state

    interpreter.process("220 mail.example.com ESMTP Exim 4.63\r\n")
    assert_equal :ehlo, interpreter.state
    assert_equal 'EHLO localhost.local', delegate.read
    
    interpreter.process("250-mail.example.com Hello\r\n")
    interpreter.process("250-RANDOMCOMMAND\r\n")
    interpreter.process("250-EXAMPLECOMMAND\r\n")
    interpreter.process("250-SIZE 52428800\r\n")
    interpreter.process("250-PIPELINING\r\n")
    interpreter.process("250-STARTTLS\r\n")
    interpreter.process("250 HELP\r\n")
    
    assert_equal true, delegate.tls_support?
    
    assert_equal :starttls, interpreter.state
    assert_equal 'STARTTLS', delegate.read
    assert_equal false, delegate.started_tls?
    
    interpreter.process("220 TLS go ahead\r\n")
    assert_equal true, delegate.started_tls?
    
    assert_equal :ehlo, interpreter.state
  end

  def test_tls_connection_without_support
    delegate = SMTPDelegate.new(:use_tls => true)
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    interpreter.process("220 mail.example.com ESMTP Exim 4.63\r\n")
    assert_equal 'EHLO localhost.local', delegate.read
    
    interpreter.process("250-mail.example.com Hello\r\n")
    interpreter.process("250 HELP\r\n")
    
    assert_equal false, delegate.started_tls?

    assert_equal :ready, interpreter.state
  end

  def test_basic_smtp_plaintext_auth_accepted
    delegate = SMTPDelegate.new(:username => 'tester@example.com', :password => 'tester')
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)
    
    assert delegate.requires_authentication?

    assert_equal :initialized, interpreter.state

    interpreter.process("220 mail.example.com SMTP Server 1.0\r\n")
    assert_equal 'HELO localhost.local', delegate.read

    assert_equal :helo, interpreter.state, interpreter.error
    
    interpreter.process("250-mail.example.com Hello\r\n")
    interpreter.process("250 HELP\r\n")
    
    assert_equal false, delegate.started_tls?

    assert_equal :auth, interpreter.state
    assert_equal "AUTH PLAIN AHRlc3RlckBleGFtcGxlLmNvbQB0ZXN0ZXI=", delegate.read
    
    interpreter.process("235 Accepted\r\n")
    
    assert_equal :ready, interpreter.state
  end

  def test_basic_esmtp_plaintext_auth_accepted
    delegate = SMTPDelegate.new(:username => 'tester@example.com', :password => 'tester')
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    interpreter.process("220 mail.example.com ESMTP Exim 4.63\r\n")
    assert_equal 'EHLO localhost.local', delegate.read
    
    interpreter.process("250-mail.example.com Hello\r\n")
    interpreter.process("250 HELP\r\n")
    
    assert_equal false, delegate.started_tls?

    assert_equal :auth, interpreter.state
    assert_equal "AUTH PLAIN AHRlc3RlckBleGFtcGxlLmNvbQB0ZXN0ZXI=", delegate.read
    
    interpreter.process("235 Accepted\r\n")
    
    assert_equal :ready, interpreter.state
  end

  def test_basic_esmtp_plaintext_auth_rejected
    delegate = SMTPDelegate.new(:username => 'tester@example.com', :password => 'tester')
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    interpreter.process("220 mx.google.com ESMTP\r\n")
    assert_equal 'EHLO localhost.local', delegate.read
    
    interpreter.process("250-mx.google.com at your service\r\n")
    interpreter.process("250 HELP\r\n")
    
    assert_equal false, delegate.started_tls?

    assert_equal :auth, interpreter.state
    assert_equal "AUTH PLAIN AHRlc3RlckBleGFtcGxlLmNvbQB0ZXN0ZXI=", delegate.read
    
    interpreter.process("535-5.7.1 Username and Password not accepted. Learn more at\r\n")
    interpreter.process("535 5.7.1 http://mail.google.com/support/bin/answer.py?answer=14257\r\n")
    
    assert_equal '5.7.1 Username and Password not accepted. Learn more at http://mail.google.com/support/bin/answer.py?answer=14257', interpreter.error

    assert_equal :quit, interpreter.state
    
    interpreter.process("221 2.0.0 closing connection\r\n")
    
    assert_equal :terminated, interpreter.state
    assert_equal true, delegate.closed?
  end

  def test_unexpected_response
    delegate = SMTPDelegate.new(:username => 'tester@example.com', :password => 'tester')
    interpreter = Remailer::SMTP::Client::Interpreter.new(:delegate => delegate)

    interpreter.process("530 Go away\r\n")
    
    assert_equal :terminated, interpreter.state
    assert_equal true, delegate.closed?
  end
end
