# encoding: utf-8

module Trinity
  module Transitions
    class FlowRejectFromBuild < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true
        valid
      end

      def handle(issue)

        applog :warn, 'We have issues that do not match release status'

        issue.fixed_version_id = ''
        issue.notes = "Задача не попадает в билд #{version.name}."

        issue.save
        issue
      end

    end
  end
end