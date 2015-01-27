require_relative '../helper'

class RemailerSMTPClientTest < MiniTest::Test
  def test_connect
    engine do
      debug = { }
      connected_host = nil

      connection = Remailer::SMTP::Client.open(
        TestConfig.options[:public_smtp_server][:host],
        debug: self.debug_channel, 
        connect: lambda { |success, host| connected_host = host }
      )

      after_complete_trigger = false

      connection.close_when_complete!
      connection.after_complete do
        after_complete_trigger = true
      end

      assert_equal :initialized, connection.state
      assert !connection.error?
      assert !connection.closed?

      assert_eventually(30) do
        connection.closed?
      end

      assert_equal TestConfig.options[:public_smtp_server][:identifier], connected_host

      assert_equal true, after_complete_trigger

      assert_equal 35882577, connection.max_size
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
        debug: self.debug_channel,
        error: lambda { |code, message|
          error_received = [ code, message ]
        },
        on_connect: lambda { on_connect = true },
        on_error: lambda { on_error = true },
        timeout: 1
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
        debug: self.debug_channel,
        error: lambda { |code, message|
          error_received = [ code, message ]
        },
        timeout: 1
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
        TestConfig.options[:smtp_server][:host],
        port: TestConfig.options[:smtp_server][:port] || Remailer::SMTP::Client::SMTP_PORT,
        debug: self.debug_channel,
        username: TestConfig.options[:smtp_server][:username],
        password: TestConfig.options[:smtp_server][:password]
      )

      after_complete_trigger = false

      connection.close_when_complete!
      connection.after_complete do
        after_complete_trigger = true
      end

      assert_equal :initialized, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.closed?
      end

      assert_equal TestConfig.options[:public_smtp_server][:identifier], connection.remote

      assert_equal true, after_complete_trigger

      assert_equal 35882577, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_via_proxy
    engine do
      debug = { }

      connection = Remailer::SMTP::Client.open(
        TestConfig.options[:public_smtp_server][:host],
        debug: self.debug_channel,
        proxy: {
          proto: :socks5,
          host: TestConfig.options[:proxy_server]
        }
      )

      after_complete_trigger = false

      connection.close_when_complete!
      connection.after_complete do
        after_complete_trigger = true
      end

      assert_equal :initialized, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.closed?
      end

      assert_equal TestConfig.options[:public_smtp_server][:identifier], connection.remote

      assert_equal true, after_complete_trigger

      assert_equal 35882577, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_and_send_after_start
    engine do
      connection = Remailer::SMTP::Client.open(
        TestConfig.options[:public_smtp_server][:host],
        debug: self.debug_channel
      )

      assert_equal :initialized, connection.state

      assert_eventually(10) do
        connection.state == :ready
      end

      result_code = nil
      callback_received = false
      
      connection.send_email(
        TestConfig.options[:sender],
        TestConfig.options[:recipient],
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
        TestConfig.options[:public_smtp_server][:host],
        debug: self.debug_channel
      )

      assert_equal :initialized, connection.state
      assert !connection.error?

      result_code = nil
      connection.send_email(
        TestConfig.options[:sender],
        TestConfig.options[:recipient],
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
        TestConfig.options[:public_smtp_server][:host],
        debug: self.debug_channel
      )

      assert_equal :initialized, connection.state
      assert !connection.error?

      result_code = [ ]

      10.times do |n|
        recipient_parts = TestConfig.options[:sender].split(/@/)
        recipient_parts.insert(1, n)

        connection.send_email(
          TestConfig.options[:sender],
          '%s+%d@%s' % recipient_parts,
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
        TestConfig.options[:public_smtp_server][:host],
        debug: self.debug_channel
      )

      assert_equal :initialized, connection.state

      callback_made = false
      result_code = nil

      connection.send_email(
        TestConfig.options[:sender],
        TestConfig.options[:recipient],
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
From: #{TestConfig.options[:sender]}
To: Remailer Test <#{TestConfig.options[:receiver]}>
Message-Id: <hfLkcIByfjYoNIxCO7DMsxBTX9svsFHikIOfAiYy@#{TestConfig.options[:sender].split(/@/).last}>
Subject: Example Subject
Mime-Version: 1.0
Content-Type: text/plain
Auto-Submitted: auto-generated

This is a very boring message. It is dreadfully dull.
__END__

    example.gsub(/\n/, "\r\n")
  end
end
