# encoding: utf-8

module Trinity
  class CLI < Thor
    include Thor::Actions

    class_option :config, :aliases => '-c', :type => :string, :required => true
    class_option :verbose, :aliases => '-v', :type => :boolean, :default => true
    class_option :interactive, :aliases => '-i', :type => :boolean, :default => false

    @@merge_statuses = {
        :ok => 'MERGE_STATUS_OK',
        :failed => 'MERGE_STATUS_FAILED',
        :conflict => 'MERGE_STATUS_CONFLICT',
        :empty => 'MERGE_STATUS_EMPTY_RELATED_BRANCH'
    }

    desc 'merge PROJECT_NAME QUERY_ID', 'Helper utility to merge branches'
    method_option :hours_to_qa, :default => 3, :aliases => '-qa', :desc => "Hours to QA-team to test the build"

    def merge(project_name, query_id)

      loop do

        say '================ BEGIN MERGE PROCEDURE ===================', :bold

        say "Project name: #{project_name}"
        say "Query ID: #{query_id}"

        # Fetching chacnges from origin
        say 'Fetching changes from origin' if options[:verbose]
        `git fetch origin`
        say 'Current branch is: %s' % Trinity::Git.current_branch if options[:verbose]

        # Choosing time for new build branch
        now = Time.now
        if now.hour < 9
          date = Chronic.parse('today at 9am')
        elsif now.hour >= 9 and now.hour < (17-options[:hours_to_qa].to_i)
          date = Chronic.parse('today at 17pm')
        else
          date = Chronic.parse('tomorrow at 9am')
        end

        say "Choosing time: #{date}" if options[:verbose]

        # Check if there is a current unmerged build branch.
        say "Check if there is current build branch" if options[:verbose]
        regex = /\A\*?\s?build_.*\Z/
        say "Regex: #{regex.inspect}" if options[:verbose]
        build = `git branch -a`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| regex.match(a) }.last

        (exit 1 if no?('Continue (yes/no): ')) if options[:interactive]

        # If there is no current build, create it.
        # Otherwise process current build.
        # Checklist:
        #  * if build pushed & merged, delete build branch and exit the loop
        #  * if build not pushed & not merged, begin merging features
        #  * if build pushed & not merged but it is time to QA - push build and delete local branch


        if build.empty?
          say "No current build" if options[:verbose]

          build_name = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"

          say "Creating new build branch #{build_name}" if options[:verbose]
          Trinity::Git.create_build_branch(date)
        else

          say "We have build #{build}" if options[:verbose]

          say "Parsing time from current build #{build}" if options[:verbose]
          # Parse date from build name
          buf = build.split("_").drop(1)
          date_buf = buf.take(3).join('-').concat ' '
          time_buf = buf.last
          date_string = date_buf.concat(time_buf)
          parsed_date = Chronic.parse(date_string)

          abort "Couldn't parse time" if parsed_date.nil?

          say "Parsed time: #{parsed_date}" if options[:verbose]

          build_pushed = Trinity::Git.is_branch_pushed(build)
          say "Check if build is pushed to origin: #{build_pushed.inspect}" if options[:verbose]

          (exit 1 if no?('Continue (yes/no): ')) if options[:interactive]

          `git checkout master`
          build_merged = Trinity::Git.is_branch_merged(build)
          say "Check if build is already merged: #{build_merged.inspect}" if options[:verbose]

          (exit 1 if no?('Continue (yes/no): ')) if options[:interactive]

          if build_merged and build_pushed
            say "Build #{build} is MERGED to master and PUSHED to origin" if options[:verbose]
            say "Deleting build branch #{build}" if options[:verbose]
            say `git branch -d #{build}`, :yellow
            say 'Creating new build branch' if options[:verbose]
            Trinity::Git.create_build_branch(date)

            next
          else
            say "Build #{build} is NOT MERGED to master. Switching to #{build}" if options[:verbose]
            `git checkout #{build}`
          end

          time_to_qa = (parsed_date-now)/3600.round <= options[:hours_to_qa]
          say "Is it time to QA build?: #{time_to_qa}", :yellow if options[:verbose]

          if time_to_qa
            `git push origin #{build}`
            `git checkout master`
            `git branch -D #{build}`
            next
          end

          (exit 1 if no?('Continue (yes/no): ')) if options[:interactive]

        end

        exit 1 if 'master'.match(build)

        (exit 1 if no?('Continue (yes/no): ')) if options[:interactive]

        puts 'Current branch is: %s' % Trinity::Git.current_branch
        version = Trinity::Redmine.create_version(project_name, Trinity::Git.current_branch)

        exit 1 if version.id.nil?

        puts 'Merging master into current branch'
        `git merge master`

        puts 'Begin merging features'

        puts 'Fetching issues and remote branches'
        issues_to_build = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {:project => project_name})

        puts "Issues loaded: #{issues_to_build.count.to_s}"

        issues_to_build.each do |issue|

          ret = merge_feature_branch(issue, version)

          issue = ret[:issue]
          status = ret[:merge_status]

          if status.eql? @@merge_statuses[:ok] #or
            say 'Changing issue parameters'
            say "Version ID: #{version.id}" if options[:verbose]
            # Adding issue into build
            issue.fixed_version_id = version.id
            say 'Status ID: 16 [HARDCODED]' if options[:verbose]
            issue.status_id = 16
          end

          puts "Saving issue"
          issue.save

          say status.inspect if options[:verbose]

          sleep 2
        end

        #`git push origin #{build}`

        #say "Check if there is #{options[:hours_to_qa]} hours to QA: #{time_to_qa.inspect}" if options[:verbose]
        #if time_to_qa
        #  say 'Pushing build to QA' if options[:verbose]
        #  say 'Sending notice' if options[:verbose]
        #  MAIL_NOTICE_HASH.each do |recipient|
        #    Mail.deliver do
        #      from 'trinity@happylab.ru'
        #      to recipient
        #      subject "#{project_name} // build info"
        #      content_type 'text/html; charset=UTF-8'
        #      body "Build <a href='http://r.itcreativoff.com/versions/#{version.id}'>#{build_name}</a> is ready for QA in http://tvkinoradio.pre.itcreativoff.com"
        #    end
        #    say "The message was send to #{recipient}" if options[:verbose]
        #  end
        #end

        #if options[:verbose]
        #  say "Success count: #{merged.count.to_s}"
        #  say "Fail count: #{fail.count.to_s}"
        #  say "No remote found: #{no_remote.count.to_s}"
        #end

        say '================ END MERGE PROCEDURE ===================', :bold

        say 'Waiting 1 minute', :cyan
        sleep 60
      end
    end


    desc 'rebuild PROJECT_NAME BRANCH_NAME', 'Helper utility to rebuild build branches'

    def rebuild(project_name, branch, status = 'open')

      version = find_version project_name, branch, status

      if version.status.eql? 'locked'
        say 'This version is LOCKED and want to be released'
      elsif !version.nil?
        say "Found version: #{version.name} (#{version.id}) [#{version.status}]", :green
        version_id = version.id.strip.to_i

        say 'Preparing build branch'

        `git checkout master`
        `git branch -D #{branch}`
        `git push origin :#{branch}` if Trinity::Git.is_branch_pushed(branch)
        `git checkout -b #{branch}`

        issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version_id})
        say "Loaded issues: #{issues.count.to_s}" if options[:verbose]

        issues.each do |issue|
          say "Processing issue: #{issue.id} #{issue.subject}"
          say "Is status correct (On prerelease - OK)?: #{issue.status.id.to_i.eql? 15}"

          # On prerelease (Status id: 16), On prerelease - OK (Status id: 15) [HARDCODED]
          if (15..16).include?(issue.status.id.to_i)
            say "Merging issue: #{issue.id} v#{issue.fixed_version.name}" if options[:verbose]

            ret = merge_feature_branch(issue, version)

            issue.save if !ret[:merge_status].eql? @@merge_statuses[:ok]

            say ret[:merge_status], (ret[:merge_status].eql? @@merge_statuses[:ok] ? :green : :red) if options[:verbose]
          else
            issue.fixed_version_id = nil
            say "Removing fixed_version_id: #{issue.fixed_version.id}"

            issue.notes = 'Задача была отклонена. В билд не попадает.'
            say "Adding notes: #{issue.notes}"

            say "Saving issue"
            issue.save
          end
        end

        `git push origin #{branch}`

      else
        say "Couldn't find version you supplied"
      end
    end

    desc 'release PROJECT_NAME', 'Release helper utility'

    def release(project_name)

      versions = fetch_versions(project_name, 'locked')

      versions.each do |version|

        version_name = version.name
        release_tag = version.name.split('_').drop(1).join('_')

        `git checkout #{version_name}`

        issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i})
        say "Loaded issues: #{issues.count.to_s}" if options[:verbose]

        issues.each do |issue|

          need_rebuild = false
          # Check if all issues are On prerelease - Ok
          if !issue.status.id.to_i.eql? 15
            need_rebuild = true
          end

          if need_rebuild
            say "Some issues are not in correct status (On prerelease - Ok [Id: 15]). [TODO] Start rebuilding build...", :red
            # TODO auto rebuild
            exit 1
          end

          # TODO Check if issue is merged to build

          next if issue.status.id.to_i.eql? 5
          # Status closed (Status id: 5) [HARDCODED]
          issue.status_id = 5
          issue.save
        end


        `git flow release start #{version.name}`
        `git merge --no-ff #{version_name}`
        `git flow release finish -m '#{release_tag}' #{version.name}`
        `git branch -d #{version_name}`
        `git push`

      end

    end

    private

    def merge_feature_branch(issue, version)

      ret = {
          :issue => issue,
          :merge_status => @@merge_statuses[:ok]
      }

      puts "---"
      puts "Start processing feature #{issue.id}"

      related_branch = find_issue_related_branch(issue)

      puts "Related branch: #{related_branch}"

      ret[:merge_status] = @@merge_statuses[:empty]
      return ret if related_branch.empty?

      puts 'Merging branch'
      branch_merged = `git branch -r --merged`.split("\n").map { |br| br.strip }.select { |br| related_branch.match(br) }

      if branch_merged.empty?
        puts "Merging #{issue.id} branch #{related_branch}"
        merge_status = `git merge --no-ff #{related_branch}`

        say merge_status if options[:verbose]

        conflict = /CONFLICT|fatal/

        if conflict.match(merge_status)

          puts "Error while automerging branch #{related_branch}"
          puts "Resetting HEAD"
          `git reset --hard`

          say "Trying to load changesets" if options[:verbose]
          current = Trinity::Issue.find(issue.id, :params => {:include => 'changesets'})
          say "Changeset loaded: #{!current.changesets.empty?.inspect}" if options[:verbose]

          # Try to assign developer
          if !current.changesets.empty? && current.changesets.last.user.id
            say "Assigned to ID: #{current.assigned_to.id}" if options[:verbose]
            say "Changeset last user ID: #{current.changesets.last.user.id}" if options[:verbose]
            issue.assigned_to_id = current.changesets.last.user.id
            issue.notes = "Имеются неразрашенные конфликты.\nНеобходимо слить ветку задачи #{related_branch} и ветку master.\n#{merge_status}"
          else
            issue.notes = "Необходимо ВРУЧНУЮ отклонить задачу.\nИмеются неразрашенные конфликты.\nНужно слить ветку задачи #{related_branch} и ветку master.\n#{merge_status}"
          end

          say 'Status ID: 6 [HARDCODED]' if options[:verbose]
          issue.status_id = 6 # Отклонена

          ret = {
              :issue => issue,
              :merge_status => @@merge_statuses[:conflict]
          }
          return ret
        end

      else
        say 'Branch already merged. Next...'
      end

      say "End processing feature #{issue.id} #{issue.subject}"
      say '---'

      ret = {
          :issue => issue,
          :merge_status => @@merge_statuses[:ok]
      }
      return ret
    end

    def fetch_versions(project_name, status = 'open')

      versions = []

      Trinity::Version.prefix = '/projects/' + project_name + '/'
      Trinity::Version.find(:all).each do |v|

        next if v.status.eql? 'closed'

        v.name.strip!
        v.status.strip!

        #say "#{v.status}.eql? #{status}: #{v.status.eql? status}", :yellow if options[:verbose]

        if v.status.eql? status
          say "Found #{status} version: #{v.name} (#{v.id}) [#{v.status}]", :yellow if options[:verbose]
          versions << v
        end
      end

      versions
    end

    def find_version(project_name, branch, status = 'open')

      versions = fetch_versions(project_name, status)

      version = nil
      Trinity::Version.prefix = '/projects/' + project_name + '/'
      versions.each do |v|

        v.name.strip!
        v.status.strip!

        if v.name.eql? branch and v.status.eql? status
          version = v
          break
        end
      end
      version
    end

    def find_issue_related_branch(issue)
      feature_regexp = /origin\/feature\/#{issue.id}_*/
      `git branch -r`.split("\n").map { |n| n.strip }.select { |a| feature_regexp.match(a) }.join
    end

  end
end
