require 'rubygems'
require 'rake'

require 'bundler/setup'

Bundler.require

begin
  require 'juwelier'

  Juwelier::Tasks.new do |gem|
    gem.name = "remailer"
    gem.summary = %Q{Reactor-Ready SMTP Mailer}
    gem.description = %Q{EventMachine Mail Agent for SMTP and IMAP}
    gem.email = "tadman@postageapp.com"
    gem.homepage = "http://github.com/postageapp/remailer"
    gem.authors = [ "Scott Tadman" ]

    gem.files.exclude(
      '.travis.yml',
      'test/config.yml.enc'
    )
  end

  Juwelier::GemcutterTasks.new

rescue LoadError
  puts "Juwelier (or a dependency) not available. Install it with: gem install Juwelier"
end

require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

task default: :test
