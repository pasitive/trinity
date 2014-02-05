# Send a notice to a Jabber address.
#
# host     - The String hostname of the Jabber server.
# port     - The Integer port of the Jabber server (default: 5222).
# from_jid - The String Jabber ID of the sender.
# password - The String password of the sender.
# to_jid   - The String Jabber ID of the recipient.
# subject  - The String subject of the message (default: "God Notification").

CONTACT_DEPS[:jabber] = ['xmpp4r']
CONTACT_DEPS[:jabber].each do |d|
  require d
end

module Trinity
  module Contacts
    class Jabber < Contact

      class << self
        attr_accessor :host, :port, :from_jid, :password, :to_jid, :subject
        attr_accessor :format
      end

      self.port = 5222
      self.subject = 'Trinity Notification'

      self.format = lambda do |message, time, priority, category, host|
        text = "Message: #{message}\n"
        text += "Host: #{host}\n" if host
        text += "Priority: #{priority}\n" if priority
        text += "Category: #{category}\n" if category
        text
      end

      attr_accessor :host, :port, :from_jid, :password, :to_jid, :subject

      def valid?
        valid = true
        valid
      end

      def notify(message, time, priority, category, host)
        body = Jabber.format.call(message, time, priority, category, host)

        message = ::Jabber::Message.new(arg(:to_jid), body)
        message.set_type(:normal)
        message.set_id('1')
        message.set_subject(arg(:subject))

        jabber_id = ::Jabber::JID.new("#{arg(:from_jid)}/Trinity")

        client = ::Jabber::Client.new(jabber_id)
        client.connect(arg(:host), arg(:port))
        client.auth(arg(:password))
        client.send(message)
        client.close

      rescue Object => e
        if e.respond_to?(:message)
          logmsg(:info, "failed to send jabber message to #{arg(:to_jid)}: #{e.message}")
        else
          logmsg(:info, "failed to send jabber message to #{arg(:to_jid)}: #{e.class}")
        end
        logmsg(:debug, e.backtrace.join("\n"))
      end

    end
  end
end