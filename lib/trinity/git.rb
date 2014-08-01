module Trinity
  class Git
    class << self

      def fetch
        `git fetch --all`
      end

      def status
        `git status`
      end

      def create_build_branch(date)
        build = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"
        `git checkout -b #{build}`
        build
      end

      def find_issue_related_branch(issue)
        feature_regexp = /origin\/feature\/#{issue.id}[^\d]_*/
        branches = `git branch -r`.split("\n").map { |n| n.strip }.select { |a| feature_regexp.match(a) }
        branches
      end

      def current_branch
        `git rev-parse --abbrev-ref HEAD`
      end

      def checkout_branch(branch)
        `git checkout #{branch}`
      end

      def is_branch_pushed(branch)
        !`git branch -r`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |b| b.match(branch) }.empty?
      end

      def is_branch_merged(branch, merged_to = 'master')
        `git checkout #{merged_to}`
        !`git branch -r --merged`.split("\n").map { |n| n.strip }.select { |b| b.match(branch) }.empty?
      end

      def config(k)
        hsh = {}
        `git config --list`.split("\n").each do |line|
          (key, *values) = line.split('=')
          hsh[key] = values.join('=')
        end
        hsh[k] if !hsh[k].nil?
      end
    end
  end
end
