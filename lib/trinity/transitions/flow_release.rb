# encoding: utf-8

module Trinity
  module Transitions
    class FlowRelease < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true
        valid
      end

      def handle(issue)

        issue.notes = "Задача ##{issue.id} полностью реализована"
        issue.status_id = @config['redmine']['status']['closed']

        issue.save
        issue
      end

    end
  end
end