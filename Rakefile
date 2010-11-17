require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "remailer"
    gem.summary = %Q{Reactor-Ready SMTP Mailer}
    gem.description = %Q{EventMachine capable SMTP engine}
    gem.email = "scott@twg.ca"
    gem.homepage = "http://github.com/twg/remailer"
    gem.authors = [ "Scott Tadman" ]
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

task :test => :check_dependencies

task :default => :test
