class Remailer::Interpreter
  # == Constants ============================================================

  # == Submodules ===========================================================
  
  autoload(:StateProxy, 'remailer/interpreter/state_proxy')
  
  # == Properties ===========================================================
  
  attr_reader :state
  attr_reader :error

  # == Class Methods ========================================================
  
  def self.initial_state
    @initial_state || :initialized
  end
  
  def self.initial_state=(state)
    @initial_state = state
  end
  
  def self.states
    @states ||= {
      :initialized => { },
      :terminated => { }
    }
  end
  
  def self.state_defined?(state)
    !!self.states[state]
  end
  
  def self.states_defined
    self.states.keys
  end
  
  def self.state(state, &block)
    config = self.states[state] = { }
    
    StateProxy.new(config, &block)
  end

  # == Instance Methods =====================================================

  def initialize(options = nil)
    @delegate = (options and options[:delegate])
    
    enter_state(options && options[:state] || self.class.initial_state)
  end
  
  def enter_state(state)
    if (@state)
      leave_state(@state)
    end
    
    @state = state
    
    trigger_callbacks(state, :enter)
    
    if (@state != :terminated)
      if (trigger_callbacks(state, :terminate))
        enter_state(:terminated)
      end
    end
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
    else
      @error = "No handler for response #{object.inspect} in state #{@state.inspect}"
      enter_state(:terminated)

      false
    end
  end
  
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
end
