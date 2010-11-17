require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class RemailerTest < Test::Unit::TestCase
  def test_connect
    engine do
      connection = Remailer::Connection.open('twgmail.twg.ca', :close => true)
      
      assert_equal :connecting, connection.state
      assert !connection.error?

      assert_eventually(15) do
        connection.state == :closed
      end
    end
  end

  def test_connect_and_send_after_start
    engine do
      connection = Remailer::Connection.open('twgmail.twg.ca')
      
      assert_equal :connecting, connection.state
      
      assert_eventually(10) do
        connection.state == :ready
      end

      result_code = nil
      connection.send_email(
        'sender@postageapp.com',
        'random+test@twg.ca',
        example_message
      ) do |c|
        result_code = c
      end

      assert_eventually(5) do
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
        'random+test@twg.ca',
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
To: info@twg.ca
Message-Id: <hfLkcIByfjYoNIxCO7DMsxBTX9svsFHikIOfAiYy@twgmail.twg.ca>
Subject: Example Subject
Mime-Version: 1.0
Content-Type: text/plain
X-Mailer: PostageApp 1.0 (http://postageapp.com)
Auto-Submitted: auto-generated
Sender: postageapp@mail.postageapp.com

This is a very boring message. It is dreadfully dull.
__END__

    example.gsub(/\n/, "\r\n")
  end
end
