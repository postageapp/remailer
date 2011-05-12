# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{remailer}
  s.version = "0.4.5"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Scott Tadman"]
  s.date = %q{2011-05-12}
  s.description = %q{EventMachine SMTP Mail User Agent}
  s.email = %q{scott@twg.ca}
  s.extra_rdoc_files = [
    "README.rdoc"
  ]
  s.files = [
    ".document",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "lib/remailer.rb",
    "lib/remailer/connection.rb",
    "lib/remailer/connection/smtp_interpreter.rb",
    "lib/remailer/connection/socks5_interpreter.rb",
    "lib/remailer/interpreter.rb",
    "lib/remailer/interpreter/state_proxy.rb",
    "remailer.gemspec",
    "test/config.example.rb",
    "test/helper.rb",
    "test/unit/remailer_connection_smtp_interpreter_test.rb",
    "test/unit/remailer_connection_socks5_interpreter_test.rb",
    "test/unit/remailer_connection_test.rb",
    "test/unit/remailer_interpreter_state_proxy_test.rb",
    "test/unit/remailer_interpreter_test.rb",
    "test/unit/remailer_test.rb"
  ]
  s.homepage = %q{http://github.com/twg/remailer}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.6.0}
  s.summary = %q{Reactor-Ready SMTP Mailer}
  s.test_files = [
    "test/config.example.rb",
    "test/helper.rb",
    "test/unit/remailer_connection_smtp_interpreter_test.rb",
    "test/unit/remailer_connection_socks5_interpreter_test.rb",
    "test/unit/remailer_connection_test.rb",
    "test/unit/remailer_interpreter_state_proxy_test.rb",
    "test/unit/remailer_interpreter_test.rb",
    "test/unit/remailer_test.rb"
  ]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<eventmachine>, [">= 0"])
    else
      s.add_dependency(%q<eventmachine>, [">= 0"])
    end
  else
    s.add_dependency(%q<eventmachine>, [">= 0"])
  end
end

