require 'socket'
require 'eventmachine'

class Remailer::IMAP::Server < EventMachine::Protocols::LineAndTextProtocol
  # == Submodules ===========================================================
  
  autoload(:Interpreter, 'remailer/imap/server/imap_interpreter')

  # == Constants ============================================================

  # == Class Methods ========================================================

  # == Instance Methods =====================================================
  
end
