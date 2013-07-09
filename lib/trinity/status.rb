module Trinity

  require 'rake'
  require 'yaml'
  require 'trinity/git'
  require 'trinity/redmine'
  require 'chronic'

  class Status
    class << self

      def checker(config)

        project_name = 'tvkinoradio-web'
        query_id = 72 # In shot - ok

        #loop do

        puts 'Fetching changes from origin'
        `git fetch origin`
        puts 'Current branch is: %s' % Trinity::Git.current_branch

        now = Time.now
        if now.hour < 12
          date = Chronic.parse('today at 2pm')
        elsif now.hour >= 12 and now.hour < 18
          date = Chronic.parse('today at 6pm')
        else
          date = Chronic.parse('tomorrow at 2pm')
        end

        date = Chronic.parse('now')
        build_name = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"

        # Check if there is current build branch
        regex = /^\*?\s?build_.*/
        build = `git branch -a`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| regex.match(a) }.join

        puts "We have build: " + build if !build.empty?

        `git checkout master`

        Trinity::Git.create_build_branch(date) if build.empty?
        `git checkout #{build}` if !build.empty?

=begin
          if `git branch --merged`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| build.match(a) }.empty?
            puts "Branch #{build} not merged"
          else
            `git branch -d #{build}`
            puts "Merged #{build}. Deleting."
            Trinity::Git.create_build_branch(date)
          end
=end

        version = Trinity::Redmine.create_version(project_name, Trinity::Git.current_branch)

        exit 1 if version.id.nil?
        #exit 1 if (build.empty? || build.nil?)

        puts 'Current branch is: %s' % Trinity::Git.current_branch

        `git merge master`

        puts 'Begin merging features'

        puts 'Fetching issues and remote branches'
        issues_to_build = Trinity::Redmine.fetch_issues_by_filter_id(project_name, query_id)

        merged = []
        conflicts = []
        fail = []
        no_remote = []

        puts "Issues loaded: #{issues_to_build.count.to_s}"

        issues_to_build.each do |issue|

          puts "---"
          puts "Start processing feature #{issue.id}"

          feature_regexp = /origin\/feature\/#{issue.id}_*/
          related_branch = `git branch -r`.split("\n").map { |n| n.strip }.select { |a| feature_regexp.match(a) }.join

          puts "Related branch: " + related_branch

          if related_branch.empty?
            no_remote << issue.id
            next
          end

          remote_branch_name = related_branch

          puts 'Merging branch'
          branch_merged = `git branch -r --merged`.split("\n").map { |br| br.strip }.select { |br| remote_branch_name.match(br) }

          if branch_merged.empty?
            puts "Merging #{issue.id} branch #{remote_branch_name}"
            merge_status = `git merge --no-ff #{remote_branch_name}`

            puts merge_status

            conflict = /CONFLICT/

            if conflict.match(merge_status)
              puts "Error while automerging branch #{remote_branch_name}"
              puts "Resetting HEAD"
              `git reset --hard`

              #TODO Change status
              #issue.status_id = opened_id
              issue.notes = merge_status
            end

          else
            puts "Next..."
          end

          puts 'Changing issue parameters'
          # Adding issue into build
          issue.fixed_version_id = version.id
          #issue.status_id = 16

          puts "Saving issue"
          issue.save

          puts "End processing feature #{issue.id} #{issue.subject}"
          puts "---"

          sleep 2
        end

        puts 'Pushing build'
        `git push origin #{Trinity::Git.current_branch}`

        puts "Waiting 5 minutes"
        #sleep 300
        #end

        puts 'Success count: ' + merged.count.to_s
        puts 'Fail count: ' + fail.count.to_s
        puts 'No remote found: ' + no_remote.count.to_s

      end

    end
  end
end
