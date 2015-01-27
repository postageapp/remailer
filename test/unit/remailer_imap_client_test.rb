require_relative '../helper'

class RemailerIMAPClientTest < MiniTest::Test
  def test_connect
    skip
    
    engine do
      debug = { }
      
      client = Remailer::IMAP::Client.open(
        TestConfig.options[:imap_server][:host],
        debug: self.debug_channel, 
        connect: lambda { |success, host| connected_host = host }
      )
      
      assert client
      
      assert_eventually(30) do
        client.connected?
      end
      
      capabilities = nil
      
      client.capability do |list|
        capabilities = list
      end
      
      assert_eventually(10) do
        capabilities
      end
      
      assert_equal %w[ IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN X-GM-EXT-1 XYZZY SASL-IR AUTH=XOAUTH AUTH=XOAUTH2 ], capabilities
      
      # -- LOGIN ------------------------------------------------------------
      
      login_status = nil
      
      client.login(TestConfig.options[:smtp_server][:username], TestConfig.options[:smtp_server][:password]) do |status, message|
        login_status = status
      end
      
      assert_eventually(10) do
        login_status
      end
      
      assert_equal 'OK', login_status
      
      # -- LIST -------------------------------------------------------------

      list = nil
    
      client.list do |status, message, additional|
        list = additional
      end

      assert_eventually(10) do
        list
      end
    
      assert list.find { |i| i[0] == 'INBOX' }
      
      # -- EXAMINE -----------------------------------------------------------
      
      examine_status = nil

      client.examine('INBOX') do |status, message, additional|
        examine_status = status
      end
      
      assert_eventually(10) do
        examine_status
      end
      
      assert_equal 'OK', examine_status

      # -- SELECT -----------------------------------------------------------
      
      select_status = nil

      client.select('INBOX') do |status, message, additional|
        select_status = status
      end
      
      assert_eventually(10) do
        select_status
      end
      
      assert_equal 'OK', select_status
      
      # -- IDLE ------------------------------------------------------------
      
      idle_status = nil
      
      idle = client.idle do |status|
        idle_status = status
      end
      
      assert_equal nil, idle_status
      
      idle.call
      
      assert_eventually(5) do
        idle_status
      end
      
      assert_equal 'OK', idle_status

      # -- FETCH -----------------------------------------------------------
      
      fetch_status = nil

      client.fetch(2..5) do |status, message, additional|
        fetch_status = status
      end
      
      assert_eventually(10) do
        fetch_status
      end
      
      assert_equal 'OK', fetch_status
    end
  end
end
