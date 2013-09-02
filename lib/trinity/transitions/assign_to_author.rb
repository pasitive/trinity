# encoding: utf-8

module Trinity
  module Transitions
    class AssignToAuthor < Transition

      def check(issue, params)
        valid = true

        if !issue.respond_to? 'assigned_to'
          applog(:warn, "Issue #{issue.id} is not responding to assigned_to")
          valid = false
        end

        if issue.assigned_to.id.eql? issue.author.id
          applog(:info, "Issue #{issue.id} already assigned to author")
          valid = false
        end

        valid
      end

      def handle(issue)

        date = Date.parse(Time.now.to_s)

        msg = "#{issue.id};"

        self.notes = "Ваша задача #{self.issue_link(issue)} требует проверки. Установлена новая дата выполнения."

        issue.done_ratio = 100
        msg += "Done ratio: #{issue.done_ratio};"
        issue.due_date = date.strftime('%Y-%m-%d')
        msg += "Due date: #{issue.due_date};"
        issue.assigned_to_id = issue.author.id
        msg += "Notes: #{self.notes}"
        issue.notes = self.notes
        applog(:info, msg)
        issue.save

        # Notifing author
        author = Trinity::Redmine::Users.find(issue.author.id)

        Trinity.contact(:jabber) do |c|
          c.name = author.login
          c.to_jid = author.mail
        end

        self.notify << author.login

        issue
      end

    end
  end
end