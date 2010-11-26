class Remailer::Interpreter::StateProxy
  STATIC_CLASSES = [ String, Fixnum, NilClass, TrueClass, FalseClass, Float ].freeze
  
  def initialize(options, &block)
    @options = options
    
    instance_eval(&block) if (block_given?)
  end
  
  def enter(&block)
    @options[:enter] ||= [ ]
    @options[:enter] << block
  end
  
  def interpret(response, &block)
    @options[:interpret] ||= [ ]
    @options[:interpret] << [ response, block ]
  end
  
  def default(&block)
    @options[:default] ||= [ ]
    @options[:default] << block
  end

  def leave(&block)
    @options[:leave] ||= [ ]
    @options[:leave] << block
  end
  
  def terminate(&block)
    @options[:terminate] ||= [ ]
    @options[:terminate] << block
  end

protected
  def rebind(options)
    @options = options
  end
end
