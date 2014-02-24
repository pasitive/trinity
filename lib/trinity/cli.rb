# encoding: utf-8

module Trinity
  class CLI < Thor
    include Thor::Actions

    class_option :config, :aliases => '-c', :type => :string
    class_option :verbose, :aliases => '-v', :type => :boolean, :default => true
    class_option :hours_to_qa, :default => 2, :aliases => '-qa', :desc => "Hours to QA-team to test the build"

    @@merge_statuses = {
        :ok => 'MERGE_STATUS_OK',
        :failed => 'MERGE_STATUS_FAILED',
        :conflict => 'MERGE_STATUS_CONFLICT',
        :empty => 'MERGE_STATUS_EMPTY_RELATED_BRANCH',
        :already_merged => 'MERGE_STATUS_ALREADY_MERGED'
    }

    @@rebuild_statuses = {
        :ok => 'REBUILD_STATUS_OK',
        :failed => 'REBUILD_STATUS_FAILED',
    }

    @@release_statuses = {
        :ok => 'RELEASE_STATUS_OK',
        :need_rebuild => 'RELEASE_STATUS_NEED_REBUILD',
        :empty_build => 'RELEASE_STATUS_EMPTY_BUILD',
    }

    TYPE_BLOCKS = "blocks"
    TYPE_BLOCKED = "blocked"

    TYPES = {
        TYPE_BLOCKS => {:name => :label_blocks, :sym_name => :label_blocked_by,
                        :order => 4, :sym => TYPE_BLOCKED},
        TYPE_BLOCKED => {:name => :label_blocked_by, :sym_name => :label_blocks,
                         :order => 5, :sym => TYPE_BLOCKS, :reverse => TYPE_BLOCKS},
    }.freeze

    def initialize(*)
      super
      # Loading config file
      @config = Trinity::Config.load({:file => options[:config]})
    end

    desc 'version', 'Get version number'

    def version
      p VERSION.to_s
    end

    desc 'transition', 'Utility to help handle issue statuses and assign issues to the employers'

    def transition
      loop do
        begin
          @config['transitions'].each do |project, transitions|
            logmsg(:info, "Processing project: #{project}")
            transitions.each do |tn, params|
              t = Trinity::Transition.generate(tn)
              logmsg(:info, "Processing transition #{t.friendly_name}")
              t.config = @config

              if project.to_s.eql? 'all'
                issues = Trinity::Redmine.fetch_issues_by_filter_id(params['query_id'], {})
              else
                issues = Trinity::Redmine.fetch_issues_by_filter_id(params['query_id'], {:project_id => project})
              end

              logmsg(:info, "Issues loaded: #{issues.count}")

              issues.each do |issue|
                check = t.check(issue, params)
                t.handle(issue) if check
                notify(t.notify, t.notes) if check
              end

            end
          end
        rescue ActiveResource::ServerError => e
          msg = "We have problem while handling response from Redmine server. Sleep for a while."
          notify('admins', msg)
          sleep 60
        rescue Exception => e
          logmsg(:error, "#{e.message} #{e.backtrace}")
        ensure
          puts "Sleep for a while..."
          sleep 30
        end
      end
    end

    desc 'cycle', 'Main workflow cycle'
    method_option :project_name, :required => true, :aliases => '-p', :desc => 'Project name'
    method_option :query_id, :required => true, :aliases => '-q', :desc => 'Query id for ready to QA features'
    method_option :release_locked, :default => false, :aliases => '-r', :desc => 'Release locked versions'

    def cycle
      logmsg :info, 'Start workflow cycle'
      loop do #Global workflow loop

        if time_to_release or options[:release_locked]

          logmsg :info, "Time to release: #{Time.now.to_s}"
          versions = Trinity::Redmine::Version.fetch_versions(options[:project_name], 'locked')

          if !versions.count.eql? 0
            logmsg :info, 'Start processing versions'

            versions.each do |version|
              logmsg :info, "Start processing version #{version.name}"
              release_status = release options[:project_name], version.name

              case release_status
                when @@release_statuses[:empty_build]
                  version.delete
                  break
                else
                  rebuild options[:project_name], version.name, 'locked'

                  version_name = version.name
                  release_tag = version_name.split('_').drop(1).join('_')

                  `git flow release start #{version_name}`
                  `git merge --no-ff #{version_name}`
                  `git flow release finish -m '#{release_tag}' #{version_name}`
                  `git branch -d #{version_name}`
                  `git push`

                  issues = Trinity::Redmine.fetch_issues({:project_id => options[:project_name], :fixed_version_id => version.id})
                  issues.select { |i| i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }.each do |issue|
                    t = Trinity::Transition.generate('flow_release')
                    t.config = @config
                    t.version = version
                    t.handle(issue) if t.check(issue, {})
                  end

                  Trinity::Redmine::Version.prefix = '/'
                  version.status = 'closed'
                  version.save
              end

            end #end processing versions
          else
            logmsg :info, 'No versions to release'
          end
        else
          logmsg :info, "It's not time to release"
        end

        # Merge
        merge options[:project_name], options[:query_id]

        logmsg :info, 'Sleep for 60 seconds'
        sleep 60

      end
    end

    desc 'merge PROJECT_NAME QUERY_ID', 'Helper utility to merge branches'

    def merge(project_name, query_id)
      read_git_flow_config

      log_block('Merge', 'start')

      logmsg :info, "Project ID: #{project_name}, Query ID: #{query_id}"

      # Check if there is a current unmerged build branch.
      logmsg :info, 'Check if there is current build branch'
      regex = /\A\*?\s?build_.*\Z/
      build = `git branch -a`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| regex.match(a) }.last

      build = prepare_build(project_name, build)

      Trinity::Git::fetch

      version = Trinity::Redmine::Version.find_version(project_name, build)

      if version.nil?
        logmsg :warn, 'Version is nil'
        return false
      end

      # Prevent merging to master
      if Trinity::Git.current_branch.match(@master_branch)
        logmsg :warn, "Current branch is #{@master_branch}. Stop merging directly into #{@master_branch}"
        return false
      end

      logmsg :info, "Current branch is: #{Trinity::Git.current_branch}"

      logmsg :info, 'Pulling changes into current branch'
      `git branch --set-upstream-to=origin/#{build} #{build}`
      `git pull`

      logmsg :info, "Merging #{@master_branch} into current branch"
      merge_status = `git merge --no-ff origin/#{@master_branch}`

      return false if is_conflict(merge_status, ['project' => project_name, 'current_branch' => Trinity::Git.current_branch, 'merging_branch' => "origin/#{@master_branch}"])

      logmsg :info, 'Begin merging features'

      logmsg :info, 'Fetching issues and remote branches'
      issues_to_build = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {:project_id => project_name})

      logmsg :info, "Issues loaded: #{issues_to_build.count.to_s}"

      issues_to_build.each do |issue|

        log_block("Feature #{issue.id} merge", 'start')

        ret = merge_feature_branch(issue, version, project_name)
        handle_merge_status(issue, ret[:version], ret)

        build = ret[:version]

        log_block("Feature #{issue.id} merge", 'end')
        sleep 2
      end

      `git push origin #{build}`

      log_block('Merge', 'end')

      return true
    end

    desc 'rebuild PROJECT_NAME BRANCH_NAME STATUS', 'Helper utility to rebuild build branches'
    method_option :skip_status, :default => false, :type => :boolean, :aliases => '-s', :desc => 'Skip statuses'
    method_option :force, :default => false, :type => :boolean, :aliases => '-f', :desc => 'Delete branch completely and merge features again. Use with caution.'

    def rebuild(project_name, branch, status = 'open')

      read_git_flow_config

      log_block('Rebuild', 'start')

      version = Trinity::Redmine::Version.find_version project_name, branch, status

      if !version.nil?
        logmsg :info, "Found version: #{version.name} (#{version.id}) [#{version.status}]"
        version_id = version.id.strip.to_i

        logmsg :info, 'Preparing build branch'

        if options[:force]
          `git checkout #{@master_branch}`
          `git branch -D #{branch}`
          `git push origin :#{branch}` if Trinity::Git.is_branch_pushed(branch)
          `git checkout -b #{branch}`
        else
          `git checkout #{branch}`
        end

        Trinity::Git::fetch

        `git pull origin/#{branch}`
        merge_status = `git merge origin/#{@master_branch}`
        `git reset --hard` if is_conflict(merge_status)

        issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version_id})
        logmsg :info, "Loaded issues: #{issues.count.to_s}"

        issues.each do |issue|
          logmsg :info, "Processing issue: #{issue.id} #{issue.subject}"
          logmsg :info, "Is status correct (On prerelease - OK)?: #{issue.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok']}"

          correct_status = [
              @config['redmine']['status']['on_prerelease_ok']
          ]

          if correct_status.include?(issue.status.id.to_i) or options[:skip_status]

            logmsg :info, "Merging issue: #{issue.id} v#{issue.fixed_version.name}"

            ret = merge_feature_branch(issue, version, project_name)

            if status.eql? @@merge_statuses[:conflict]
              t = Trinity::Transition.generate('flow_merge_conflict')
              t.config = @config
              t.version = ret[:version]
              t.handle(issue) if t.check(issue, ret)
            end

            logmsg :info, ret[:merge_status]
          else
            t = Trinity::Transition.generate('flow_reject_from_build')
            t.config = @config
            t.version = ret[:version]
            t.handle(issue) if t.check(issue, ret)
          end
        end

        `git push origin #{branch}`

      else
        logmsg :warn, "Couldn't find version you supplied"
      end

      log_block('Rebuild', 'end')

      return @@rebuild_statuses[:ok]
    end

    desc 'release PROJECT_NAME', 'Release helper utility'

    def release(project_name, version)

      version = Trinity::Redmine::Version.find_version(project_name, version, 'locked')

      log_block("Release #{version.name}", 'start')

      version_name = version.name

      `git checkout #{version_name}`

      issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i})

      logmsg :info, "Loaded issues: #{issues.count.to_s}"

      # Check if all issues has right status
      if issues.any? { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }
        logmsg :info, 'Some issues in the build are in incorrect status'
        issues.select { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }.each do |issue|
          t = Trinity::Transition.generate('flow_reject_from_build')
          t.config = @config
          t.version = version
          t.handle(issue) if t.check(issue, {})
        end
        return @@release_statuses[:need_rebuild]
      elsif issues.count.eql? 0
        logmsg :warn, 'No issues for build'
        return @@release_statuses[:empty_build]
      else
        logmsg :info, 'Do not need to rebuild'
        return @@release_statuses[:ok]
      end

      log_block('Release', 'end')
    end

    private

    def handle_merge_status(issue, version, ret)

      logmsg :debug, "Version to handle: #{version.name}"

      case ret[:merge_status]
        when @@merge_statuses[:ok]
          t = Trinity::Transition.generate('flow_merge_ok')
        when @@merge_statuses[:conflict]
          t = Trinity::Transition.generate('flow_merge_conflict')
        when @@merge_statuses[:already_merged]
          t = Trinity::Transition.generate('flow_merge_null')
        else
          t = Trinity::Transition.generate('flow_merge_ok')
      end

      if t.nil? and !@@merge_statuses[:already_merged]
        logmsg(:fatal, "Could not generate Transition")
        abort
      end

      t.config = @config
      t.version = version
      t.handle(issue) if t.check(issue, ret)
    end

    def merge_feature_branch(issue, version, project_name)

      ret = {
          :project_name => project_name,
          :version => version,
          :issue => issue,
          :merge_status => @@merge_statuses[:ok],
          :meta => {}
      }

      related_branch = Trinity::Git.find_issue_related_branch(issue)

      logmsg :info, "Related branch: #{related_branch}"

      if issue.respond_to?(:fixed_version)

        logmsg :info, "Merging branch into build it assigned to"

        current_version_id = ret[:version].id
        issue_version_id = issue.fixed_version.id

        logmsg :debug, "Current build: #{version.name} (id: #{current_version_id})"
        logmsg :debug, "Merged branch version: #{issue.fixed_version.name} (id: #{issue_version_id})"

        logmsg :debug, "Equal versions: #{current_version_id.eql? issue_version_id}"

        if !current_version_id.eql? issue_version_id
          ret[:version] = issue.fixed_version
          `git checkout #{issue.fixed_version.name}`
        end

      end

      if !related_branch.empty?

        logmsg :info, 'Merging branch'
        branch_merged = `git branch -r --merged`.split("\n").map { |br| br.strip }.select { |br| related_branch.match(br) }

        if branch_merged.empty?

          logmsg :info, "Merging #{issue.id} branch #{related_branch} into #{ret[:version].name}"

          merge_status = `git merge --no-ff #{related_branch}`

          logmsg :info, merge_status

          conflict = /CONFLICT|fatal/

          if conflict.match(merge_status)
            logmsg :warn, "Error while automerging branch #{related_branch}"
            logmsg :info, 'Resetting HEAD'
            `git reset --hard`
            ret[:merge_status] = @@merge_statuses[:conflict]
            ret[:meta] = {
                :related_branch => related_branch,
                :merge_message => merge_status,
            }
          else
            ret[:merge_status] = @@merge_statuses[:ok]
          end

        else
          logmsg :info, 'Branch already merged. Next...'
          ret[:merge_status] = @@merge_statuses[:ok]
        end

      else
        ret[:merge_status] = @@merge_statuses[:empty]
      end

      ret[:issue] = issue

      return ret
    end

    def prepare_build(project_name, build)

      read_git_flow_config

      log_block('Prepare', 'start')

      ret = {
          :build => nil,
          :version => nil
      }

      logmsg :info, 'Fetching changes from origin'
      `git fetch origin`
      logmsg :info, 'Current branch is: %s' % Trinity::Git.current_branch

      # Choosing time for new build branch
      date = choose_date()

      # If there is no current build, create it.
      # Otherwise process current build.
      # Checklist:
      #  * if build pushed & merged, delete build branch and exit the loop
      #  * if build not pushed & not merged, begin merging features
      #  * if build pushed & not merged but it is time to QA - push build and delete local branch

      if build.nil?
        logmsg :info, 'No current build'
        build_name = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"
        build = Trinity::Git.create_build_branch(date)
        version = Trinity::Redmine.create_version(project_name, build)
        logmsg :info, "Created new build branch #{build_name}"
        return build
      else
        logmsg :info, "We have build #{build}"

        version = Trinity::Redmine::Version.find_version(project_name, build)

        if version.nil?
          version = Trinity::Redmine.create_version(project_name, build)
        end

        logmsg :info, "Found version: #{version.name}"

        if version.nil?
          logmsg :fatal, 'No version found or loaded'
          abort
        end

        build_pushed = Trinity::Git.is_branch_pushed(build)
        logmsg :info, "Check if build is pushed to origin: #{build_pushed.inspect}"

        build_merged = Trinity::Git.is_branch_merged(build, @master_branch)
        logmsg :info, "Check if build is already merged: #{build_merged.inspect}"

        build_has_no_issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i}).count.eql? 0
        logmsg :warn, "Build has NO issues: #{build_has_no_issues.inspect}"

        if build_pushed

          logmsg :info, 'Build pushed to origin'

          if build_merged and build_has_no_issues
            # New empty build
            logmsg :info, "Build #{build} has no issues. Switching to #{build} and start merging features"
            `git checkout #{build}`
          elsif !build_merged
            # New empty build
            logmsg :info, "Build #{build} is NOT MERGED to master. Switching to #{build} and start merging features"
            `git checkout #{build}`
          else
            logmsg :info, "Build #{build} is MERGED to master and PUSHED to origin"

            `git branch -d #{build}`
            logmsg :info, "Deleted build branch #{build}"

            build = Trinity::Git.create_build_branch(date)
            logmsg :info, "Created new build branch: #{build}"

            return build
          end

        else
          logmsg :info, 'Build NOT pushed to origin. Now pushing'
          `git push origin #{build}`
        end

        time_to_qa = time_to_qa(build, options[:hours_to_qa])

        logmsg :info, "Is it time to QA build?: #{time_to_qa}"

        if time_to_qa
          logmsg :info, 'Time to QA build.'

          `git push origin #{build}`
          `git checkout master`
          `git branch -D #{build}`

          logmsg :info, "Deleted branch #{build}"

          message = "Build <a href='http://r.itcreativoff.com/versions/#{version.id}'>#{build}</a>
                     is ready for QA"

          notify('qa', message)
        else
          `git checkout #{build}`
        end

        log_block('Prepare', 'end')
        return build
      end

    end

    def time_to_release
      Time.now.hour >= 17
    end

    def choose_date
      now = Time.now
      if now.hour < (17-options[:hours_to_qa].to_i)
        date = Chronic.parse('today at 17pm')
      else
        date = Chronic.parse('tomorrow at 17pm')
      end

      if date.nil?
        logmsg :error, "#{__method__}: Chronic.parse error"
        abort
      end

      logmsg :info, "Date for build: #{date}; Hours to QA: #{options[:hours_to_qa]}"
      return date
    end

    def time_to_qa(build, hours_diff)

      logmsg :info, "Hours diff: #{hours_diff}"
      logmsg :info, "Build: #{build}"

      # Parse date from build name
      buf = build.split('_').drop(1)
      date_buf = buf.take(3).join('-').concat ' '
      time_buf = buf.last
      date_string = date_buf.concat(time_buf)
      parsed_date = Chronic.parse(date_string)

      if parsed_date.nil?
        logmsg :fatal, "#{__method__} couldn't parse time"
        abort
      end

      logmsg :info, "#{__method__}: #{parsed_date}"

      (parsed_date-Time.now)/3600.round <= hours_diff
    end

    def log_block(name, state)
      logmsg :info, "[============================= #{name}: #{state} ===============================]"
    end

    # Notify all recipients of the given condition with the specified message.
    #
    # notify - The Condition.
    # message   - The String message to send.
    #
    # Returns nothing.
    def notify(notify, message)

      spec = Contact.normalize(notify)
      unmatched = []

      # Resolve contacts.
      resolved_contacts =
          spec[:contacts].inject([]) do |acc, contact_name_or_group|
            cons = Array(Trinity.contacts[contact_name_or_group] || Trinity.contact_groups[contact_name_or_group])
            unmatched << contact_name_or_group if cons.empty?
            acc += cons
            acc
          end

      # Warn about unmatched contacts.
      unless unmatched.empty?
        msg = "no matching contacts for '#{unmatched.join(", ")}'"
        logmsg(:warn, msg)
      end

      # Notify each contact.
      resolved_contacts.each do |c|
        host = `hostname`.chomp rescue 'none'
        begin
          c.notify(message, Time.now, spec[:priority], spec[:category], host)
          msg = "#{c.info ? c.info : "notification sent for contact: #{c.name}"}"
          logmsg(:info, msg % [])
        rescue Exception => e
          logmsg(:error, "#{e.message} #{e.backtrace}")
          msg = "Failed to deliver notification for contact: #{c.name}"
          logmsg(:error, msg % [])
        end
      end
    end


    private

    def is_conflict(merge_message, meta=[])
      logmsg :warn, merge_message
      conflict_pattern = /CONFLICT|fatal/

      if !conflict_pattern.match(merge_message)
        return false
      end

      message = "
      WARNING!!! Conflict while merging branches.\r\n
      You have to manually merge branches.\r\n

      #{meta}

      #{merge_message}

      "

      notify('admins', message)

      return true
    end

    def read_git_flow_config
      @master_branch = Trinity::Git.config('gitflow.branch.master')
      @develop_branch = Trinity::Git.config('gitflow.branch.develop')

      if @master_branch.nil? or @develop_branch.nil?
        notify('admins', "Error getting git flow config branches: master_branch:#{@master_branch.inspect}, develop_branch:#{@develop_branch.inspect}")
      end
    end

  end
end