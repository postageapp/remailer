class Remailer::Interpreter::StateProxy
  # == Constants ============================================================

  # == Instance Methods =====================================================
  
  # Creates a new state proxy object with a particular set of options. An
  # optional supplied block can be used to perform additional configuration,
  # and will be evaluated within the context of this new object.
  def initialize(options, &block)
    @options = options
    
    instance_eval(&block) if (block_given?)
  end
  
  # Defines a parser specification.
  def parse(spec = nil, &block)
    @options[:parser] = Remailer::Interpreter.parse(spec, &block)
  end
  
  # Defines a block that will execute when the state is entered.
  def enter(&block)
    (@options[:enter] ||= [ ]) << block
  end
  
  # Defines an interpreter block that will execute if the given response
  # condition is met.
  def interpret(response, &block)
    (@options[:interpret] ||= [ ]) << [ response, block ]
  end
  
  # Defines a default behavior that will trigger in the event no interpreter
  # definition was triggered first.
  def default(&block)
    (@options[:default] ||= [ ]) << block
  end

  # Defines a block that will execute when the state is left.
  def leave(&block)
    (@options[:leave] ||= [ ]) << block
  end
  
  # Terminates the interpreter after this state has been entered. Will execute
  # a block if one is supplied.
  def terminate(&block)
    @options[:terminate] ||= [ ]
    
    if (block_given?)
      @options[:terminate] << block
    end
  end

protected
  def rebind(options)
    @options = options
  end
end
