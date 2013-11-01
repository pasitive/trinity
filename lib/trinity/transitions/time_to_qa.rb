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

        @group_users = Trinity::Redmine::Groups.get_group_users(params['qa_group_id'])


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