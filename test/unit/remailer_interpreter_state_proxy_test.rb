require_relative '../helper'

class RemailerInterpreterStateTest < MiniTest::Test
  def test_defaults
    options = { }
    
    Remailer::Interpreter::StateProxy.new(options)

    assert_equal({ }, options)
  end
  
  def test_simple_configuration
    options = { }
    
    proxy = Remailer::Interpreter::StateProxy.new(options)

    expected = {
      enter: [ lambda { } ],
      default: [ lambda { } ],
      leave: [ lambda { } ]
    }.freeze

    proxy.enter(&expected[:enter][0])
    proxy.default(&expected[:default][0])
    proxy.leave(&expected[:leave][0])
    
    assert_equal expected, options
  end

  def test_terminal_configuration
    options = { }

    expected = {
      enter: [ lambda { } ],
      terminate: [ lambda { } ],
      leave: [ lambda { } ]
    }.freeze

    Remailer::Interpreter::StateProxy.new(options) do
      enter(&expected[:enter][0])
      terminate(&expected[:terminate][0])
      leave(&expected[:leave][0])
    end

    assert_equal expected, options
  end

  def test_interpreting_configuration
    options = { }
    
    expected = {
      enter: [ lambda { } ],
      interpret: [ [ 10, lambda { } ], [ 1, lambda { } ] ],
      default: [ lambda { } ],
      leave: [ lambda { } ]
    }.freeze

    Remailer::Interpreter::StateProxy.new(options) do
      enter(&expected[:enter][0])
      interpret(10, &expected[:interpret][0][1])
      interpret(1, &expected[:interpret][1][1])
      default(&expected[:default][0])
      leave(&expected[:leave][0])
    end

    assert_equal expected, options
  end

  def test_rebind
    options_a = { }
    options_b = { }
    
    proc = [ lambda { }, lambda { } ]
    
    proxy = Remailer::Interpreter::StateProxy.new(options_a) do
      enter(&proc[0])
    end
    
    proxy.send(:rebind, options_b)
    
    proxy.leave(&proc[1])
    
    assert_equal({ enter: [ proc[0] ] }, options_a)
    assert_equal({ leave: [ proc[1] ] }, options_b)
  end
end
