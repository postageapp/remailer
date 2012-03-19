class Remailer::SMTP::Server::Transaction
  # == Constants ============================================================
  
  ATTRIBUTES = [ :sender, :recipients, :data ].freeze

  # == Properties ===========================================================
  
  attr_accessor *ATTRIBUTES

  # == Class Methods ========================================================

  # == Instance Methods =====================================================
  
  def initialize(options = nil)
    case (options)
    when Remailer::SMTP::Server::Transaction
      ATTRIBUTES.each do |attribute|
        instance_variable_set("@#{attribute}", options.send(attribute))
      end
    when Hash
      ATTRIBUTES.each do |attr|
        instance_variable_set("@#{attribute}", options[attribute])
      end
    end
    
    self.recipients = [ self.recipients ].compact.flatten
    self.data ||= ''
  end
end
