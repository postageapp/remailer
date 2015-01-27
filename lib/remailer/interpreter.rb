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
    @states ||=
      if (superclass.respond_to?(:states))
        superclass.states.dup
      else
        {
          :initialized => { },
          :terminated => { }
        }
      end
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
  
  # This is a method to convert a spec and a block into a proper parser
  # method. If spec is specified, it should be a Fixnum, or a Regexp. A 
  # Fixnum defines a minimum size to process, useful for packed binary
  # streams, while a Regexp defines a pattern that must match before the
  # parser is engaged.
  def self.create_parser_for_spec(spec, &block)
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
    @parser = create_parser_for_spec(spec, &block)
  end
  
  # Assigns the default interpreter.
  def self.default(&block)
    @default = block if (block_given?)
  end

  # Assigns the error handler for when a specific interpretation could not be
  # found and a default was not specified.
  def self.on_error(&block)
    @on_error = block
  end
  
  # Returns the parser used when no state-specific parser has been defined.
  def self.default_parser
    @parser ||=
      case (superclass.respond_to?(:default_parser))
      when true
        superclass.default_parser
      else
        lambda { |s| _s = s.dup; s.replace(''); _s }
      end
  end
  
  # Returns the current default_interpreter.
  def self.default_interpreter
    @default ||=
      case (superclass.respond_to?(:default_interpreter))
      when true
        superclass.default_interpreter
      else
        nil
      end
  end
  
  # Returns the defined error handler
  def self.on_error_handler
    @on_error ||=
      case (superclass.respond_to?(:on_error_handler))
      when true
        superclass.on_error_handler
      else
        nil
      end
  end

  # == Instance Methods =====================================================

  # Creates a new interpreter with an optional set of options. Valid options
  # include:
  # * :delegate => Which object to use as a delegate, if applicable.
  # * :state => What the initial state should be. The default is :initalized
  # If a block is supplied, the interpreter object is supplied as an argument
  # to give the caller an opportunity to perform any initial configuration
  # before the first state is entered.
  def initialize(options = nil)
    @delegate = (options and options[:delegate])
    
    yield(self) if (block_given?)
    
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

    delegate_call(:interpreter_entered_state, self, @state)
    
    trigger_callbacks(state, :enter)
    
    # :terminated is the state, :terminate is the trigger.
    if (@state != :terminated)
      if (trigger_callbacks(state, :terminate))
        enter_state(:terminated)
      end
    end
  end
  
  # Parses a given string and returns the first interpretable token, if any,
  # or nil otherwise. If an interpretable token is found, the supplied string
  # will be modified to have that matching portion removed.
  def parse(buffer)
    instance_exec(buffer, &parser)
  end
  
  # Returns the parser defined for the current state, or the default parser.
  # The default parser simply accepts everything but this can be re-defined
  # using the class-level parse method.
  def parser
    config = self.class.states[@state]
    
    config and config[:parser] or self.class.default_parser
  end

  # Processes a given input string into interpretable tokens, processes these
  # tokens, and removes them from the input string. An optional block can be
  # given that will be called as each interpretable token is discovered with
  # the token provided as the argument.
  def process(s)
    _parser = parser

    while (parsed = instance_exec(s, &_parser))
      yield(parsed) if (block_given?)

      interpret(*parsed)

      break if (s.empty? or self.finished?)
    end
  end
  
  # Interprets a given object with an optional set of arguments. The actual
  # interpretation should be defined by declaring a state with an interpret
  # block defined.
  def interpret(*args)
    object = args[0]
    config = self.class.states[@state]
    interpreters = (config and config[:interpret])

    if (interpreters)
      match_result = nil
      
      matched, proc = interpreters.find do |response, proc|
        case (response)
        when Regexp
          match_result = response.match(object)
        when Range
          response.include?(object)
        else
          response === object
        end
      end
    
      if (matched)
        case (matched)
        when Regexp
          match_result = match_result.to_a
        
          if (match_result.length > 1)
            match_string = match_result.shift
            args[0, 1] = match_result
          else
            args[0].sub!(match_result[0], '')
          end
        when String
          args[0].sub!(matched, '')
        when Range
          # Keep as-is
        else
          args.shift
        end
      
        # Specifying a block with no arguments will mean that it waits until
        # all pieces are collected before transitioning to a new state, 
        # waiting until the continue flag is false.
        will_interpret?(proc, args) and instance_exec(*args, &proc)

        return true
      end
    end
    
    if (trigger_callbacks(@state, :default, *args))
      # Handled by default
      true
    elsif (proc = self.class.default_interpreter)
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
  
  # This method is used by interpret to determine if the supplied block should
  # be executed or not. The default behavior is to always execute but this
  # can be modified in sub-classes.
  def will_interpret?(proc, args)
    true
  end

  # Should return true if this interpreter no longer wants any data, false
  # otherwise. Subclasses should implement their own behavior here.
  def finished?
    false
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
    
    true
  end
end
