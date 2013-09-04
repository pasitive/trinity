# encoding: utf-8

module Trinity
  module Transitions
    class FlowMergeOk < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true
        valid
      end

      def handle(issue)

        applog :info, "Version ID: #{version.id}"

        # Adding issue into build
        issue.fixed_version_id = self.version.id
        applog :info, "Status ID: #{self.config['redmine']['status']['on_prerelease']}"
        issue.status_id = self.config['redmine']['status']['on_prerelease']

        handle_related_issues(issue)

        issue.save

        issue
      end

      private

      def handle_related_issues(issue)

        related_blocked_issue_ids = Trinity::Redmine::Issue.find_related_blocked_ids(issue.id)

        if !related_blocked_issue_ids.nil?

          related_blocked_issue_ids.each do |issue_id|

            related_issue = Trinity::Redmine::Issue.find(issue_id)

            applog :info, "Loaded related issue #{related_issue.id}"

            # если связная задача стоит в статусе In-Shot-Ok то мы ее тоже переводим в On Prerelease
            if related_issue.status.id.to_i.eql? self.config['redmine']['status']['in_shot_ok']
              applog :info, "Changing parameters #{related_issue.id}"
              related_issue.notes = "Переведена в статус, соответствующий статусу задачи ##{issue_id}"
              related_issue.fixed_version_id = version.id
              related_issue.status_id = self.config['redmine']['status']['on_prerelease']
              related_issue.save
            end
          end
        end

      end

    end
  end
end
