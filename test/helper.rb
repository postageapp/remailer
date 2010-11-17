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

class Test::Unit::TestCase
  def engine
    exception = nil
    
    ThreadsWait.all_waits(
      Thread.new do
        # Create a thread for the engine to run on
        EventMachine.run
      end,
      Thread.new do
        # Execute the test code in a separate thread to avoid blocking
        # the EventMachine loop.
        begin
          yield
        rescue Object => exception
        ensure
          EventMachine.stop_event_loop
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
end
