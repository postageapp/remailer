module Remailer::Constants
  # == Constants ============================================================
  
  LINE_REGEXP = /^.*?\r?\n/.freeze
  CRLF = "\r\n".freeze
  
  SMTP_PORT = 25
  IMAPS_PORT = 993
  SOCKS5_PORT = 1080
end
