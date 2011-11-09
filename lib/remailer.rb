module Remailer
  # == Submodules ===========================================================
  
  autoload(:SMTP, 'remailer/smtp')
  autoload(:IMAP, 'remailer/imap')
  autoload(:Interpreter, 'remailer/interpreter')
end
