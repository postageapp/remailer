require File.expand_path(File.join(*%w[ .. helper ]), File.dirname(__FILE__))

class ExampleDelegate
  include TestTriggerHelper
  
  attr_accessor :attribute
  
  def method_no_args
    trigger(:method_no_args)
  end

  def method_with_args(arg1, arg2)
    trigger(:method_with_args, [ arg1, arg2 ])
  end
end

class AutomaticDelegate
  include TestTriggerHelper

  def enter_initialized!
    trigger(:enter_initialized)
  end
end

class LineInterpreter < Remailer::Interpreter
  attr_reader :lines
  
  state :initialized do
    enter do
      @lines = [ ]
    end
  end
  
  parse(/^.*?\r?\n/) do |data|
    data.chomp
  end
  
  default do |line|
    @lines << line
  end
end

class ExampleInterpreter < Remailer::Interpreter
  include TestTriggerHelper

  attr_accessor :message, :reply
  
  state :initialized do
    enter do
      trigger(:enter_initialized_state)
    end
    
    interpret(:start) do
      enter_state(:start)
    end

    interpret(:branch) do
      enter_state(:branch)
    end

    leave do
      trigger(:leave_initialized_state)
    end
  end
  
  state :start do
    interpret(:stop) do |message|
      self.message = message
      enter_state(:stop)
    end
  end
  
  state :branch do
    default do |reply|
      @reply = reply
    end
  end
  
  state :stop do
    terminate
  end
end

class RemailerInterpreterTest < Test::Unit::TestCase
  def test_default_state
    assert_equal [ :initialized, :terminated ], Remailer::Interpreter.states_defined.collect { |s| s.to_s }.sort.collect { |s| s.to_sym }
    assert_equal true, Remailer::Interpreter.state_defined?(:initialized)
    assert_equal true, Remailer::Interpreter.state_defined?(:terminated)
    assert_equal false, Remailer::Interpreter.state_defined?(:unknown)

    interpreter = Remailer::Interpreter.new
    
    assert_equal :initialized, interpreter.state
  end
  
  def test_delegate
    delegate = ExampleDelegate.new

    assert delegate.triggered

    interpreter = Remailer::Interpreter.new(:delegate => delegate)
    
    assert_equal nil, delegate.attribute
    assert_equal false, delegate.triggered[:method_no_args]
    assert_equal false, delegate.triggered[:method_with_args]
    
    interpreter.send(:delegate_call, :method_no_args)
    
    assert_equal true, delegate.triggered[:method_no_args]
    assert_equal false, delegate.triggered[:method_with_args]

    interpreter.send(:delegate_call, :method_with_args, 'one', :two)
    
    assert_equal true, delegate.triggered[:method_no_args]
    assert_equal [ 'one', :two ], delegate.triggered[:method_with_args]
    
    interpreter.send(:delegate_call, :invalid_method)
    
    interpreter.send(:delegate_assign, :attribute, 'true')
    
    assert_equal 'true', delegate.attribute
  end
  
  def test_example_interpreter
    interpreter = ExampleInterpreter.new
    
    assert_equal :initialized, interpreter.state
    assert_equal true, interpreter.triggered[:enter_initialized_state]
    assert_equal false, interpreter.triggered[:leave_initialized_state]
    
    interpreter.interpret(:start)
    
    assert_equal :start, interpreter.state
    assert_equal true, interpreter.triggered[:enter_initialized_state]
    assert_equal true, interpreter.triggered[:leave_initialized_state]
    
    interpreter.interpret(:stop, 'Stop message')

    assert_equal 'Stop message', interpreter.message
    assert_equal :terminated, interpreter.state
  end
  
  def test_interpreter_can_process
    interpreter = LineInterpreter.new

    assert_equal [ ], interpreter.lines
    
    line = "EXAMPLE LINE\n"
    
    interpreter.process(line)
    
    assert_equal 'EXAMPLE LINE', interpreter.lines[-1]
    assert_equal '', line
    
    line << "ANOTHER EXAMPLE LINE\r\n"
    
    interpreter.process(line)
    
    assert_equal 'ANOTHER EXAMPLE LINE', interpreter.lines[-1]
    assert_equal '', line
    
    line << "LINE ONE\r\nLINE TWO\r\n"
    
    interpreter.process(line)
    
    assert_equal 'LINE ONE', interpreter.lines[-2]
    assert_equal 'LINE TWO', interpreter.lines[-1]
    assert_equal '', line
    
    line << "INCOMPLETE LINE"
    
    interpreter.process(line)

    assert_equal 'LINE TWO', interpreter.lines[-1]
    assert_equal "INCOMPLETE LINE", line
    
    line << "\r"
    
    interpreter.process(line)

    assert_equal 'LINE TWO', interpreter.lines[-1]
    assert_equal "INCOMPLETE LINE\r", line
    
    line << "\n"
    
    interpreter.process(line)

    assert_equal 'INCOMPLETE LINE', interpreter.lines[-1]
    assert_equal '', line
  end

  def test_default_handler_for_interpreter
    interpreter = ExampleInterpreter.new
    
    interpreter.interpret(:branch)
    
    assert_equal :branch, interpreter.state
    
    assert_equal true, interpreter.interpret(:random)
    
    assert_equal :branch, interpreter.state
    assert_equal nil, interpreter.error
    
    assert_equal :random, interpreter.reply
  end

  def test_invalid_response_for_interpreter
    interpreter = ExampleInterpreter.new
    
    assert_equal :initialized, interpreter.state
    
    interpreter.interpret(:invalid)
    
    assert_equal :terminated, interpreter.state
    assert_equal true, interpreter.error?

    assert interpreter.error.index(':initialized')
    assert interpreter.error.index(':invalid')
  end
end
