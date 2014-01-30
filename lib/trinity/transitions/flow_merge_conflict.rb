# encoding: utf-8

module Trinity
  module Transitions
    class FlowMergeConflict < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        @meta = params[:meta] if params[:meta]

        #logmsg :info, params.inspect

        project_name = params[:project_name]
        rejected_with_commit_params = self.config['transitions'][project_name]['rejected_with_commits']

        logmsg :debug, "Project name: #{project_name.inspect}"
        logmsg :debug, "Project params: #{rejected_with_commit_params.inspect}"


        if rejected_with_commit_params.nil?
          logmsg :warn, "project parameters are not set"
          logmsg :debug, params.inspect
        end

        @group_users = Trinity::Redmine::Groups.get_group_users(rejected_with_commit_params['reject_to_group_id'])

        logmsg :debug, @group_users

        if valid && @group_users.include?(issue.assigned_to.id.to_i)
          logmsg(:info, "No action needed. Assigned to user is a member of right group")
          valid = false
        end

        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets,journals'})

        if current.respond_to?(:changesets)
          last_user_id = Trinity::Redmine::Issue.get_last_user_id_from_changesets(current)
          self.notes = "Переназначено на сотрудника, который вносил изменения последним."
        end

        if current.respond_to?(:journals)
          users = Trinity::Redmine::Issue.filter_users_from_journals_by_group_id(current, @group_users)
          last_user_id = users.sample if users.size > 0
        else
          self.notes = "Мне не удалось найти сотрудника не по коммитам, не по журналу.\nВам необходимо вручную найти в истории нужного сотрудника и переназначить задачу на него."
        end

        @assign_to_id = last_user_id

        set_issue_attributes(issue)
        issue.save
        notify_internal(issue)
        issue
      end

      private

      def set_issue_attributes(issue)

        issue.assigned_to_id = @assign_to_id
        issue.notes = self.notes
        issue.priority_id = self.config['redmine']['priority']['critical']
        issue.status_id = self.config['redmine']['status']['reopened'] # Отклонена

        issue.fixed_version_id = ''
      end

      def notify_internal(issue)
        notify = [issue.author.id, @assign_to_id]
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