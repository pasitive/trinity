module Trinity
  class Transition

    attr_accessor :notify, :notes, :config

    def initialize
      self.notify = []
    end

    def self.generate(kind)
      sym = kind.to_s.capitalize.gsub(/_(.)/) { $1.upcase }.intern
      t = Trinity::Transitions.const_get(sym).new
      t
    rescue NameError
      raise NoSuchTransitionError.new("No Transition found with the class name Trinity::Transitions::#{sym}")
    end

    # Change issue parameters
    def handle(issue)
      raise AbstractMethodNotOverriddenError.new("Transition#handle must be overridden in subclasses")
    end

    # Check if need to change parameters
    def check(issue, params = {})
      raise AbstractMethodNotOverriddenError.new("Transition#check must be overridden in subclasses")
    end

    def friendly_name
      "Transition #{self.class.name.split('::').last}"
    end

    protected

    def issue_link(issue)
      issue_link = "#{self.config['redmine']['connection']['site']}/issues/#{issue.id}/"
      issue_link
    end

    def issue_shot(issue)

    end

  end
end