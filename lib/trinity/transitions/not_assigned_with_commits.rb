# encoding: utf-8

module Trinity
  module Transitions
    class NotAssignedWithCommits < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true
        if current.assigned_to.id = current.changesets.first.user.id
          applog(:warn, "Issue #{issue.id} already assigned to first commiter")
          valid = false
        end
        valid
      end

      def handle(issue)

        msg = "#{issue.id};"

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets'})

        self.notes = "Исполнителем задачи #{self.issue_link(issue)} назначен автор первого коммита."

        issue.assigned_to_id = current.changesets.first.user.id
        msg += "Assigned to: #{current.changesets.first.user.id};"
        issue.notes = self.notes
        msg += "Notes: #{self.notes}"
        applog(:info, msg)

        issue.save

        author = Trinity::Redmine::Users.find(current.changesets.first.user.id)

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