class Remailer::Interpreter::StateProxy
  STATIC_CLASSES = [ String, Fixnum, NilClass, TrueClass, FalseClass, Float ].freeze
  
  def initialize(options, &block)
    @options = options
    
    instance_eval(&block) if (block_given?)
  end
  
  def parse(spec = nil, &block)
    @options[:parser] = Remailer::Interpreter.parse(spec, &block)
  end
  
  def enter(&block)
    @options[:enter] ||= [ ]
    @options[:enter] << block
  end
  
  def interpret(response, &block)
    @options[:interpret] ||= [ ]
    
    handler =
      case (block.arity)
      when 0
        # Specifying a block with no arguments will mean that it waits until
        # all pieces are collected before transitioning to a new state, 
        # waiting until the continue flag is false.
        Proc.new { |m,c| instance_exec(&block) unless (c) }
      else
        block
      end
    
    @options[:interpret] << [ response, handler ]
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
