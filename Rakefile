require 'rubygems'
require 'rake'

require 'bundler/setup'

Bundler.require

begin
  require 'jeweler'

  Jeweler::Tasks.new do |gem|
    gem.name = "remailer"
    gem.summary = %Q{Reactor-Ready SMTP Mailer}
    gem.description = %Q{EventMachine SMTP Mail User Agent}
    gem.email = "scott@twg.ca"
    gem.homepage = "http://github.com/twg/remailer"
    gem.authors = [ "Scott Tadman" ]
    gem.add_runtime_dependency 'eventmachine'
  end

  Jeweler::GemcutterTasks.new

rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

task :default => :test
