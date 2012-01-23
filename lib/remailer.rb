module Remailer
  # == Submodules ===========================================================
  
  autoload(:AbstractConnection, 'remailer/abstract_connection')
  autoload(:Constants, 'remailer/constants')
  autoload(:IMAP, 'remailer/imap')
  autoload(:Interpreter, 'remailer/interpreter')
  autoload(:SOCKS5, 'remailer/socks5')
  autoload(:SMTP, 'remailer/smtp')
  autoload(:Support, 'remailer/support')
end
