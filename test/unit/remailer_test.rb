require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class RemailerTest < Test::Unit::TestCase
  TEST_SMTP_SERVER = 'mail.postageapp.com'.freeze
  
  def test_encode_data
    sample_data = "Line 1\r\nLine 2\r\n.\r\nLine 3\r\n.Line 4\r\n"
    
    assert_equal "Line 1\r\nLine 2\r\n..\r\nLine 3\r\n..Line 4\r\n", Remailer::Connection.encode_data(sample_data)
  end
  
  def test_connect
    engine do
      debug = { }
      
      connection = Remailer::Connection.open(
        TEST_SMTP_SERVER,
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
      
      assert_equal TEST_SMTP_SERVER, connection.remote
      
      assert_equal true, after_complete_trigger
      
      assert_equal 52428800, connection.max_size
      assert_equal :esmtp, connection.protocol
      assert_equal true, connection.tls_support?
    end
  end

  def test_connect_and_send_after_start
    engine do
      connection = Remailer::Connection.open(
        TEST_SMTP_SERVER,
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
        TEST_SMTP_SERVER,
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
      connection = Remailer::Connection.open('twgmail.twg.ca')
      
      assert_equal :connecting, connection.state
      assert !connection.error?
      
      result_code = nil
      connection.send_email(
        'sender@postageapp.com',
        'remailer+test@example.postageapp.com',
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
From: sender@postageapp.com
To: Remailer Test <remailer@twg.ca>
Message-Id: <hfLkcIByfjYoNIxCO7DMsxBTX9svsFHikIOfAiYy@twg.ca>
Subject: Example Subject
Mime-Version: 1.0
Content-Type: text/plain
Auto-Submitted: auto-generated

This is a very boring message. It is dreadfully dull.
__END__

    example.gsub(/\n/, "\r\n")
  end
end
