require 'rubygems'
require 'test/unit'

$LOAD_PATH.unshift(File.expand_path(*%w[ .. lib ]), File.dirname(__FILE__))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'timeout'
require 'thwait'
require 'rubygems'

if (Gem.available?('eventmachine'))
  gem 'eventmachine'
  require 'eventmachine'
else
  raise "EventMachine gem is not installed."
end

require 'remailer'

class Proc
  def inspect
    "\#<Proc: #{object_id}>"
  end
end

unless (Hash.new.respond_to?(:slice))
  class Hash
    def slice(*keys)
      keys.inject({ }) do |h, k|
        h[k] = self[k]
        h
      end
    end
  end
end

module TestTriggerHelper
  def self.included(base)
    base.class_eval do
      attr_reader :triggered
      
      def triggered
        @triggered ||= Hash.new(false)
      end
      
      def trigger(action, value = true)
        self.triggered[action] = value
      end
    end
  end
end

class Test::Unit::TestCase
  def engine
    exception = nil
    
    ThreadsWait.all_waits(
      Thread.new do
        Thread.abort_on_exception = true

        # Create a thread for the engine to run on
        begin
          EventMachine.run
        rescue Object => exception
        end
      end,
      Thread.new do
        # Execute the test code in a separate thread to avoid blocking
        # the EventMachine loop.
        begin
          yield
        rescue Object => exception
        ensure
          begin
            EventMachine.stop_event_loop
          rescue Object
            # Shutting down may trigger an exception from time to time
            # if the engine itself has failed.
          end
        end
      end
    )
    
    if (exception)
      raise exception
    end
  end
  
  def assert_timeout(time, message = nil, &block)
    Timeout::timeout(time, &block)
  rescue Timeout::Error
    flunk(message || 'assert_timeout timed out')
  end
  
  def assert_eventually(time = nil, message = nil, &block)
    start_time = Time.now.to_i

    while (!block.call)
      select(nil, nil, nil, 0.1)
      
      if (time and (Time.now.to_i - start_time > time))
        flunk(message || 'assert_eventually timed out')
      end
    end
  end

  def assert_mapping(map, &block)
    result_map = map.inject({ }) do |h, (k,v)|
      h[k] = yield(k)
      h
    end
    
    differences = result_map.inject([ ]) do |a, (k,v)|
      if (v != map[k])
        a << k
      end

      a
    end
    
    assert_equal map, result_map, "Difference: #{map.slice(*differences).inspect} vs #{result_map.slice(*differences).inspect}"
  end
end

require 'ostruct'

TestConfig = OpenStruct.new

config_file = File.expand_path("config.rb", File.dirname(__FILE__))

if (File.exist?(config_file))
  require config_file
else
  raise "No test/config.rb file found. Copy and modify test/config.example.rb"
end
