# encoding: utf-8

# Решенные задачи, которые переходят в цикл тестирования
# Выбирается случайный тестирощик из Группы QA в Redmine

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
          logmsg(:warn, "Group #{params['qa_group_id']} not found")
          valid = false
        end

        if valid && (!@group.respond_to? 'users')
          logmsg(:warn, "No users in group #{@group.name}")
          valid = false
        end

        @group_users = @group.users.inject([]) do |result, user|
          result << user.id.to_i
          result
        end

        if valid && @group_users.empty?
          logmsg(:warn, "No users in group #{@group.name}")
          valid = false
        end

        if valid && @group_users.include?(issue.assigned_to.id.to_i)
          logmsg(:info, "No action needed. Assigned to user is a member of #{@group.name} group")
          valid = false
        end

        valid
      end

      def handle(issue)
        self.notes = "Задача #{self.issue_link(issue)} готова и требует QA."
        set_issue_attributes(issue)
        issue.save
        notify_internal(issue)
        issue
      end

      private

      def set_issue_attributes(issue)
        date = Date.parse(Time.now.to_s)
        issue.assigned_to_id = @group_users.sample(1).join
        issue.due_date = date.strftime('%Y-%m-%d')
        issue.notes = self.notes
      end

      def notify_internal(issue)
        notify = [issue.author.id, issue.assigned_to.id]
        notify.each do |user_id|
          user = Trinity::Redmine::Users.find(user_id)
          Trinity.contact(:jabber) do |c|
            c.name = user.login
            c.to_jid = user.mail
          end
          self.notify << user.login
        end
      end

    end
  end
end