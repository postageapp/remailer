class Remailer::IMAP::Client::Interpreter < Remailer::Interpreter
  # == Constants ============================================================
  
  LINE_REGEXP = /^(.*?)\r?\n/.freeze
  RESPONSE_REGEXP = /^(\S+)(?:\s+(?:(OK|NO|BAD)\s+)?([^\r\n]*))?\r?\n/.freeze
  
  # == Class Methods ========================================================

  def self.split_reply(reply)
    if (m = reply.match(RESPONSE_REGEXP))
      parts = m.to_a
      parts.shift
      
      parts
    else
      nil
    end
  end
  
  def self.split_list_definition(string)
    m = string.match(/^\(([^\)]+)\)\s+\"((?:\\\"|\\x[0-9a-fA-F][0-9a-fA-F]|\\[abtnvfr]|.)+)\"\s+\"((?:\\\"|\\x[0-9a-fA-F][0-9a-fA-F]|\\[abtnvfr]|.)+)\"/)
    
    return unless (m)
    
    split = m.to_a
    split.shift
    split[0] = split[0].split(/\s+/)
    
    split
  end

  # == State Definitions ====================================================
  
  # Based on the RFC3501 specification with extensions
  
  parse(LINE_REGEXP) do |data|
    split_reply(data)
  end

  state :initialized do
    interpret('*') do |tag, status, message|
      delegate.connect_notification(status, message)

      enter_state(:connected)
    end
  end

  state :connected do
    interpret('*') do |tag, status, message|
      message_parts = message.split(/\s+/)
      message_key = message_parts.shift
      
      case (message_key)
      when 'CAPABILITY'
        @additional ||= [ ]
        @additional += message_parts
      when 'LIST'
        message = message.sub(/^LIST\s+/, '')

        if (split = self.class.split_list_definition(message))
          @additional ||= [ ]
          @additional << split.reverse
        end
      end
    end

    default do |tag, status, message|
      delegate.receive_response(tag, status, message, @additional)
      
      @additional = nil
    end
  end
  
  state :fetch do
    parse(LINE_REGEXP)

    enter do
      @additional = ''
    end
    
    interpret(/^\*\s+(\d+)\s+FETCH\s+(.*)/) do |uid, line|
      @additional << line
    end

    interpret(/^(\w+)\s+(OK|NO|BAD)\s+(FETCH\s+.*)/) do |tag, status, message|
      delegate.receive_response(tag, [ status, message ], @additional)
      
      @additional = nil
    end
    
    default do |line|
      @additional << line
    end
  end
  
  # == Instance Methods =====================================================
  
  def label
    'IMAP'
  end
end
