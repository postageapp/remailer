require_relative '../helper'

class RemailerIMAPClientInterpreterTest < MiniTest::Test
  def test_split_list_definition
    assert_mapping(
      '(\HasChildren \HasNoChildren) "/" "[Gmail]/All Mail"' =>
        [ %w[ \HasChildren \HasNoChildren ], "/", "[Gmail]/All Mail" ],
      '(\HasNoChildren) "/" "INBOX"' =>
        [ %w[ \HasNoChildren ], "/", "INBOX" ]
    ) do |string|
      Remailer::IMAP::Client::Interpreter.split_list_definition(string)
    end
  end
end
