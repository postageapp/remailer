require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class RemailerSMTPClientTest < Test::Unit::TestCase
  def test_connect
    engine do
      debug = { }
      connected_host = nil
      on_disconnect_triggered = false

      connection = Remailer::SMTP::Client.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR, 
        :connect => lambda { |success, host|
          connected_host = host
        },
        :on_disconnect => lambda {
          on_disconnect_triggered = true
        }
      )

      connection.close_when_complete!

      assert_equal :initialized, connection.state
      assert !connection.error?
      assert !connection.closed?

      assert_eventually(30) do
        connection.closed?
      end

      assert_equal TestConfig.smtp_server[:host], connected_host

      assert_equal true, on_disconnect_triggered

      assert_equal 52428800, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_failed_connect_no_service
    engine do
      error_received = nil
      on_error = false
      on_connect = false

      connection = Remailer::SMTP::Client.open(
        'example.com',
        :debug => STDERR,
        :error => lambda { |code, message|
          error_received = [ code, message ]
        },
        :on_connect => lambda { on_connect = true },
        :on_error => lambda { on_error = true },
        :timeout => 1
      )

      assert_eventually(3) do
        error_received
      end

      assert_equal :timeout, error_received[0]
      assert_equal :timeout, connection.error

      assert_equal false, on_connect
      assert_equal true, on_error
    end
  end

  def test_failed_connect_no_valid_hostname
    engine do
      error_received = nil

      connection = Remailer::SMTP::Client.open(
        'invalid-example-domain--x.com',
        :debug => STDERR,
        :error => lambda { |code, message|
          error_received = [ code, message ]
        },
        :timeout => 1
      )

      assert_eventually(3) do
        error_received
      end

      assert_equal :connect_error, error_received[0]
    end
  end

  def test_connect_with_auth
    engine do
      debug = { }

      connection = Remailer::SMTP::Client.open(
        TestConfig.public_smtp_server[:host],
        :port => TestConfig.public_smtp_server[:port] || Remailer::SMTP::Client::SMTP_PORT,
        :debug => STDERR,
        :username => TestConfig.public_smtp_server[:username],
        :password => TestConfig.public_smtp_server[:password]
      )

      on_disconnect_triggered = false

      connection.close_when_complete!
      connection.after_complete do
        on_disconnect_triggered = true
      end

      assert_equal :initialized, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.closed?
      end

      assert_equal TestConfig.public_smtp_server[:identifier], connection.remote

      assert_equal true, on_disconnect_triggered

      assert_equal 35651584, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_via_proxy
    engine do
      debug = { }

      on_disconnect_triggered = false

      connection = Remailer::SMTP::Client.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR,
        :proxy => {
          :proto => :socks5,
          :host => TestConfig.proxy_server
        },
        :on_disconnect => lambda {
          on_disconnect_triggered = true
        }
      )

      connection.close_when_complete!

      assert_equal :connect_to_proxy, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.closed?
      end

      assert_equal TestConfig.smtp_server[:identifier], connection.remote

      assert_equal true, on_disconnect_triggered

      assert_equal 52428800, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_and_send_after_start
    engine do
      connection = Remailer::SMTP::Client.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      assert_equal :initialized, connection.state

      assert_eventually(10) do
        connection.state == :ready
      end

      result_code = nil
      callback_received = false
      
      connection.send_email(
        'remailer+test@example.postageapp.com',
        'remailer+test@example.postageapp.com',
        example_message
      ) do |c|
        callback_received = true
        result_code = c
      end

      assert_eventually(5) do
        callback_received
      end
      
      assert_equal 250, result_code
    end
  end

  def test_connect_and_send_dotted_message
    engine do
      connection = Remailer::SMTP::Client.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      assert_equal :initialized, connection.state
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

  def test_connect_and_send_multiple
    engine do
      connection = Remailer::SMTP::Client.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      assert_equal :initialized, connection.state
      assert !connection.error?

      result_code = [ ]

      10.times do |n|
        connection.send_email(
          'remailer+from@example.postageapp.com',
          "remailer+to#{n}@example.postageapp.com",
          example_message
        ) do |c|
          result_code[n] = c
        end
      end

      assert_eventually(15) do
        result_code == [ 250 ] * 10
      end
    end
  end

  def test_connect_and_long_send
    engine do
      connection = Remailer::SMTP::Client.open(
        TestConfig.smtp_server[:host],
        :debug => STDERR
      )

      assert_equal :initialized, connection.state

      callback_made = false
      result_code = nil

      connection.send_email(
        TestConfig.sender,
        TestConfig.recipient,
        example_message + 'a' * 100000
      ) do |c|
        callback_made = true
        result_code = c
      end

      assert_eventually(30) do
        callback_made
      end
      
      assert_equal 250, result_code
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
