# encoding: utf-8

# Решенные задачи не назначенные на автора этой задачи для проверки.

module Trinity
  module Transitions
    class AssignToAuthor < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        if !issue.respond_to? 'assigned_to'
          self.notes = "Issue #{issue.id} is not responding to assigned_to"
          logmsg(:warn, self.notes)
          valid = false
        end

        if valid && (issue.assigned_to.id.eql? issue.author.id)
          valid = false
        end

        valid
      end

      def handle(issue)
        self.notes = "Ваша задача #{self.issue_link(issue)} требует проверки. Установлена новая дата выполнения."

        set_issue_attributes(issue)
        issue.save
        notify_internal(issue)

        issue
      end

      private

      def set_issue_attributes(issue)
        date = Date.parse(Time.now.to_s)
        issue.done_ratio = 100
        issue.due_date = date.strftime('%Y-%m-%d')
        issue.assigned_to_id = issue.author.id
        issue.notes = self.notes
      end

      def notify_internal(issue)
        # Notifing author
        author = Trinity::Redmine::Users.find(issue.author.id)

        Trinity.contact(:jabber) do |c|
          c.name = author.login
          c.to_jid = author.mail
        end

        self.notify << author.login
      end

    end
  end
end