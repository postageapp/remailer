class Remailer::Interpreter
  # == Constants ============================================================

  # == Exceptions ===========================================================
  
  class DefinitionException < Exception; end

  # == Submodules ===========================================================
  
  autoload(:StateProxy, 'remailer/interpreter/state_proxy')
  
  # == Properties ===========================================================
  
  attr_reader :delegate
  attr_reader :state
  attr_reader :error

  # == Class Methods ========================================================
  
  # Defines the initial state for objects of this class.
  def self.initial_state
    @initial_state || :initialized
  end
  
  # Can be used to reassign the initial state for this class. May be easier
  # than re-defining the initial_state method.
  def self.initial_state=(state)
    @initial_state = state
  end
  
  # Returns the states that are defined as a has with their associated
  # options. The default keys are :initialized and :terminated.
  def self.states
    @states ||= {
      :initialized => { },
      :terminated => { }
    }
  end
  
  # Returns true if a given state is defined, false otherwise.
  def self.state_defined?(state)
    !!self.states[state]
  end
  
  # Returns a list of the defined states.
  def self.states_defined
    self.states.keys
  end
  
  # Defines a new state for this class. A block will be executed in the
  # context of a StateProxy that is used to provide a simple interface to
  # the underlying options. A block can contain calls to enter and leave,
  # or default, which do not require arguments, or interpret, which requries
  # at least one argument that will be the class-specific object to interpret.
  # Other paramters may be supplied by the class.
  def self.state(state, &block)
    config = self.states[state] = { }
    
    StateProxy.new(config, &block)
  end
  
  def self.parser_for_spec(spec, &block)
    case (spec)
    when nil
      block
    when Fixnum
      lambda do |s|
        if (s.length >= spec)
          part = s.slice!(0, spec)
          block.call(part)
        end
      end
    when Regexp
      lambda do |s|
        if (m = spec.match(s))
          part = m.to_s
          part = s.slice!(0, part.length)
          block.call(part)
        end
      end
    else
      raise DefinitionException, "Invalid specification for parse declaration: #{spec.inspect}"
    end
  end
  
  # Defines a parser for this interpreter. The supplied block is executed in
  # the context of a parser instance.
  def self.parse(spec = nil, &block)
    @parser = parser_for_spec(spec, &block)
  end
  
  # Returns the currently defined parser. Should not need to be def called
  # directly.
  def self.parser
    @parser ||= lambda { |s| s }
  end
  
  def self.default(&block)
    @default = block if (block_given?)
  end

  def self.default_interpreter
    @default
  end
  
  def self.on_error(&block)
    @on_error = block
  end
  
  def self.on_error_handler
    @on_error
  end

  # == Instance Methods =====================================================

  # Creates a new interpreter with an optional set of options. Valid options
  # include:
  # * :delegate => Which object to use as a delegate, if applicable.
  # * :state => What the initial state should be. The default is :initalized
  def initialize(options = nil)
    @delegate = (options and options[:delegate])
    
    enter_state(options && options[:state] || self.class.initial_state)
  end
  
  # Enters the given state. Will call the appropriate leave_state trigger if
  # one is defined for the previous state, and will trigger the callbacks for
  # entry into the new state. If this state is set as a terminate state, then
  # an immediate transition to the :terminate state will be performed after
  # these callbacks.
  def enter_state(state)
    if (@state)
      leave_state(@state)
    end
    
    @state = state
    
    trigger_callbacks(state, :enter)
    
    if (@state != :terminated)
      if (trigger_callbacks(state, :terminated))
        enter_state(:terminated)
      end
    end
  end
  
  # Parses a given string into interpretable tokens.
  def parse(s)
    instance_exec(s, &parser)
  end
  
  # Returns the parser defined for the current state, or the default parser
  # if one is defined.
  def parser
    config = self.class.states[@state]
    
    config and config[:parser] or self.class.parser
  end

  # The input string is
  # expected to have the parsed component removed.
  def process(s)
    _parser = parser

    while (parsed = s.empty? ? false : instance_exec(s, &_parser))
      interpret(*parsed)
    end
  end
  
  # Interprets a given object with an optional set of arguments. The actual
  # interpretation should be defined by declaring a state with an interpret
  # block defined.
  def interpret(object, *args)
    config = self.class.states[@state]
    callbacks = (config and config[:interpret])
    
    if (callbacks)
      matched, proc = callbacks.find do |on, proc|
        object == on
      end
    
      if (matched)
        instance_exec(*args, &proc)

        return true
      end
    end
    
    if (trigger_callbacks(@state, :default, *([ object ] + args)))
      # Handled by default
      true
    elsif (proc = self.class.default)
      instance_exec(*args, &proc)
    else
      if (proc = self.class.on_error_handler)
        instance_exec(*args, &proc)
      end

      @error = "No handler for response #{object.inspect} in state #{@state.inspect}"
      enter_state(:terminated)

      false
    end
  end
  
  # Returns true if an error has been generated, false otherwise. The error
  # content can be retrived by calling error.
  def error?
    !!@error
  end
  
protected
  def delegate_call(method, *args)
    @delegate and @delegate.respond_to?(method) and @delegate.send(method, *args)
  end
  
  def delegate_assign(property, value)
    method = :"#{property}="
    
    @delegate and @delegate.respond_to?(method) and @delegate.send(method, value)
  end

  def leave_state(state)
    trigger_callbacks(state, :leave)
  end
  
  def trigger_callbacks(state, type, *args)
    config = self.class.states[state]
    callbacks = (config and config[type])
    
    return unless (callbacks)

    callbacks.compact.each do |proc|
      instance_exec(*args, &proc)
    end
  end
end
