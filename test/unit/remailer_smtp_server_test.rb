require_relative '../helper'

class RemailerSMTPServerTest < MiniTest::Test
  def random_server_port
    @server_port ||= 9000 + rand(4096)

    @server_port += 1
  end

  def test_bind
    engine do
      server_port = random_server_port
      
      server = Remailer::SMTP::Server.bind(nil, server_port)
      
      assert server
    end
  end

  def test_connect
    engine do
      server_port = random_server_port

      remote_ip = nil
    
      server = Remailer::SMTP::Server.bind(
        '127.0.0.1',
        server_port,
        on_connect: lambda { |_remote_ip| remote_ip = _remote_ip }
      )
    
      assert server
      
      connected_host = nil

      client = Remailer::SMTP::Client.open(
        '127.0.0.1',
        port: server_port,
        debug: self.debug_channel, 
        connect: lambda { |success, host| connected_host = host }
      )

      assert client
      
      assert_eventually(30) do
        connected_host
      end
      
      assert_equal '127.0.0.1', connected_host
      assert_equal '127.0.0.1', remote_ip
    end
  end

  def test_transaction
    engine do
      server_port = random_server_port

      transaction = nil
    
      server = Remailer::SMTP::Server.bind(
        '127.0.0.1',
        server_port,
        on_transaction: lambda { |_transaction| transaction = _transaction }
      )
    
      assert server
      
      client = Remailer::SMTP::Client.open(
        '127.0.0.1',
        port: server_port,
        debug: self.debug_channel
      )
      
      sender = 'sender@example.com'.freeze
      recipient = 'recipient@example.net'.freeze
      content = "Subject: Re: Test Message\r\n\r\nTest message.\r\n\r\n.test\r\n.\r\n".freeze
      
      client.send_email(sender, recipient, content)
      
      assert_eventually(30) do
        transaction
      end
      
      assert_equal sender, transaction.sender
      assert_equal [ recipient ], transaction.recipients
      assert_equal content + Remailer::Constants::CRLF, transaction.data
    end
  end
end
