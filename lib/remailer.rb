module Remailer
  # == Submodules ===========================================================
  
  autoload(:AbstractConnection, 'remailer/abstract_connection')
  autoload(:Constants, 'remailer/constants')
  autoload(:EmailAddress, 'remailer/email_address')
  autoload(:Interpreter, 'remailer/interpreter')
  autoload(:IMAP, 'remailer/imap')
  autoload(:SMTP, 'remailer/smtp')
  autoload(:SOCKS5, 'remailer/socks5')
  autoload(:Support, 'remailer/support')
end
