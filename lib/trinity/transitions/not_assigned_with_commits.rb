# encoding: utf-8

module Trinity
  module Transitions
    class NotAssignedWithCommits < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        @current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets'})

        if !@current.respond_to? 'assigned_to'
          self.notes = "Issue #{issue.id} is not responding to assigned_to"
          applog(:warn, self.notes)
          valid = false
        end

        if valid && (!@current.respond_to? 'changesets')
          self.notes = "Issue #{issue.id} is not responding to changesets"
          applog(:warn, self.notes)
          valid = false
        end


        if valid && (issue.assigned_to.id.to_i.eql? @current.changesets.first.user.id.to_i)
          applog(:warn, "Issue #{issue.id} already assigned to first commiter")
          valid = false
        end

        valid
      end

      def handle(issue)

        msg = "#{issue.id};"

        self.notes = "Исполнителем задачи #{self.issue_link(issue)} назначен автор первого коммита."

        issue.assigned_to_id = @current.changesets.first.user.id
        msg += "Assigned to: #{@current.changesets.first.user.id};"
        issue.notes = self.notes
        msg += "Notes: #{self.notes}"
        applog(:info, msg)

        issue.save

        author = Trinity::Redmine::Users.find(@current.changesets.first.user.id)

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