require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class RemailerTest < Test::Unit::TestCase
  def test_module_loaded
    assert Remailer
  end
end
