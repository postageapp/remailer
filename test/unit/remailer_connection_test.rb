require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class RemailerConnectionTest < Test::Unit::TestCase
  def test_split_reply
    assert_mapping(
      '250 OK' => [ 250, 'OK', false ],
      '250 Long message' => [ 250, 'Long message', false ],
      'OK' => nil,
      '100-Example' => [ 100, 'Example', true ]
    ) do |reply|
      Remailer::Connection.split_reply(reply)
    end
  end

  def test_encode_data
    sample_data = "Line 1\r\nLine 2\r\n.\r\nLine 3\r\n.Line 4\r\n"
    
    assert_equal "Line 1\r\nLine 2\r\n..\r\nLine 3\r\n..Line 4\r\n", Remailer::Connection.encode_data(sample_data)
  end
  
  def test_base64
    assert_mapping(
      'example' => 'example',
      "\x7F" => "\x7F",
      nil => ''
    ) do |example|
      Remailer::Connection.base64(example).unpack('m')[0]
    end
  end
  
  def test_encode_authentication
    assert_mapping(
      %w[ tester tester ] => 'AHRlc3RlcgB0ZXN0ZXI='
    ) do |username, password|
      Remailer::Connection.encode_authentication(username, password)
    end
  end

  def test_connect
    engine do
      debug = { }

      connection = Remailer::Connection.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      after_complete_trigger = false

      connection.close_when_complete!
      connection.after_complete do
        after_complete_trigger = true
      end

      assert_equal :connecting, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.state == :closed
      end

      assert_equal TestConfig.smtp_server[:host], connection.remote

      assert_equal true, after_complete_trigger

      assert_equal 52428800, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_failed_connect
    engine do
      error_received = nil

      connection = Remailer::Connection.open(
        'example.com',
        :debug => STDERR,
        :error => lambda { |code, message|
          error_received = [ code, message ]
        },
        :timeout => 1
      )

      assert_eventually(3) do
        error_received
      end

      assert_equal :timeout, error_received[0]
    end
  end

  def test_connect_with_auth
    engine do
      debug = { }

      connection = Remailer::Connection.open(
        TestConfig.public_smtp_server[:host],
        :port => TestConfig.public_smtp_server[:port] || Remailer::Connection::SMTP_PORT,
        :debug => STDERR,
        :username => TestConfig.public_smtp_server[:username],
        :password => TestConfig.public_smtp_server[:password]
      )

      after_complete_trigger = false

      connection.close_when_complete!
      connection.after_complete do
        after_complete_trigger = true
      end

      assert_equal :connecting, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.state == :closed
      end

      assert_equal TestConfig.public_smtp_server[:identifier], connection.remote

      assert_equal true, after_complete_trigger

      assert_equal 35651584, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_via_proxy
    engine do
      debug = { }

      connection = Remailer::Connection.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR,
        :proxy => {
          :proto => :socks5,
          :host => TestConfig.proxy_server
        }
      )

      after_complete_trigger = false

      connection.close_when_complete!
      connection.after_complete do
        after_complete_trigger = true
      end

      assert_equal :connecting, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.state == :closed
      end

      assert_equal TestConfig.smtp_server[:identifier], connection.remote

      assert_equal true, after_complete_trigger

      assert_equal 52428800, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_and_send_after_start
    engine do
      connection = Remailer::Connection.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      assert_equal :connecting, connection.state

      assert_eventually(10) do
        connection.state == :ready
      end

      result_code = nil
      connection.send_email(
        'remailer+test@example.postageapp.com',
        'remailer+test@example.postageapp.com',
        example_message
      ) do |c|
        result_code = c
      end

      assert_eventually(5) do
        result_code == 250
      end
    end
  end

  def test_connect_and_send_dotted_message
    engine do
      connection = Remailer::Connection.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      assert_equal :connecting, connection.state
      assert !connection.error?

      result_code = nil
      connection.send_email(
        'remailer+test@example.postageapp.com',
        'remailer+test@example.postageapp.com',
        example_message + "\r\n\.\r\nHam sandwich.\r\n"
      ) do |c|
        result_code = c
      end

      assert_eventually(15) do
        result_code == 250
      end
    end
  end

  def test_connect_and_long_send
    engine do
      connection = Remailer::Connection.open(TestConfig.smtp_server[:host])

      assert_equal :connecting, connection.state

      result_code = nil
      connection.send_email(
        TestConfig.sender,
        TestConfig.receiver,
        example_message + 'a' * 100000
      ) do |c|
        result_code = c
      end

      assert_eventually(15) do
        result_code == 250
      end
    end
  end

protected
  def example_message
    example = <<__END__
Date: Sat, 13 Nov 2010 02:25:24 +0000
From: #{TestConfig.sender}
To: Remailer Test <#{TestConfig.receiver}>
Message-Id: <hfLkcIByfjYoNIxCO7DMsxBTX9svsFHikIOfAiYy@#{TestConfig.sender.split(/@/).last}>
Subject: Example Subject
Mime-Version: 1.0
Content-Type: text/plain
Auto-Submitted: auto-generated

This is a very boring message. It is dreadfully dull.
__END__

    example.gsub(/\n/, "\r\n")
  end
end
