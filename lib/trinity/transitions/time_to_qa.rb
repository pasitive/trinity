# encoding: utf-8

module Trinity
  module Transitions
    class TimeToQa < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        # Check if group valid
        @group = Trinity::Redmine::Groups.find(params['qa_group_id'], :params => {:include => 'users'})

        if !@group.respond_to? 'name'
          applog(:warn, "Group #{params['qa_group_id']} not found")
          valid = false
        end

        if !@group.respond_to? 'users'
          applog(:warn, "No users in group #{@group.name}")
          valid = false
        end

        @group_users = @group.users.inject([]) do |result, user|
          result << user.id.to_i
          result
        end

        if @group_users.empty?
          applog(:warn, "No users in group #{@group.name}")
          valid = false
        end

        if @group_users.include?(issue.assigned_to.id.to_i)
          applog(:info, "No action needed. Assigned to user is a member of #{@group.name} group")
          valid = false
        end

        valid
      end

      def handle(issue)

        date = Date.parse(Time.now.to_s)

        self.notes = "Задача #{self.issue_link(issue)} готова и требует QA."

        issue.assigned_to_id = @group_users.sample(1).join
        issue.due_date = date.strftime('%Y-%m-%d')
        issue.notes = self.notes

        issue.save

        notify = [issue.author.id, issue.assigned_to.id]

        notify.each do |user_id|

          user = Trinity::Redmine::Users.find(user_id)

          Trinity.contact(:jabber) do |c|
            c.name = user.login
            c.to_jid = user.mail
          end

          self.notify << user.login
        end

        issue
      end

    end
  end
end