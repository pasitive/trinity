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

    desc 'foo', 'qew'

    def foo
      issue = Trinity::Redmine::Issue.find(4423)
      related_branch = Trinity::Git.find_issue_related_branch(issue)
      p related_branch.split('/').last
    end

    def initialize(*)
      super
      @config = Trinity::Config.load({:file => options[:config]})
      applog :info, 'Initialization - OK'
    end

    desc 'version', 'Version number'

    def version
      p VERSION
    end

    desc 'init', 'Setup trinity'

    def init

    end

    desc 'transition', 'Help to check statuses & transitions'

    def transition
      loop do
        begin
          @config['transitions'].each do |project, transitions|
            applog(:info, "Processing project: #{project}")
            transitions.each do |tn, params|
              t = Trinity::Transition.generate(tn)
              applog(:info, "Processing transition #{t.friendly_name}")
              t.config = @config
              if project.to_s.eql? 'all'
                issues = Trinity::Redmine.fetch_issues_by_filter_id(params['query_id'], {})
              else
                issues = Trinity::Redmine.fetch_issues_by_filter_id(params['query_id'], {:project_id => project})
              end
              applog(:info, "Issues loaded: #{issues.count}")
              issues.each do |issue|
                check = t.check(issue, params)

                t.handle(issue) if check
                notify(t.notify, t.notes) if check
              end
            end
          end
        rescue ActiveResource::ServerError => e
          puts "We have problem while handling response from Redmine server. Sleep for a while."
          sleep 60
        rescue Exception => e
          applog(:error, "#{e.message} #{e.backtrace}")
        ensure
          puts "Sleep for a while..."
          sleep 30
        end
      end
    end

    desc 'cycle', 'Helper utility to merge branches'
    method_option :project_name, :required => true, :aliases => '-p', :desc => 'Project name'
    method_option :query_id, :required => true, :aliases => '-q', :desc => 'Query id for ready to QA features'
    method_option :release_locked, :default => false, :aliases => '-r', :desc => 'Release locked versions'

    def cycle
      applog :info, 'Start workflow cycle'
      loop do #Global workflow loop

        if time_to_release or options[:release_locked]

          applog :info, "Time to release: #{Time.now.to_s}"
          versions = Trinity::Redmine::Version.fetch_versions(options[:project_name], 'locked')

          if !versions.count.eql? 0
            applog :info, 'Start processing versions'

            versions.each do |version|
              applog :info, "Start processing version #{version.name}"
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
            applog :info, 'No versions to release'
          end
        else
          applog :info, "It's not time to release"
        end

        # Merge
        merge options[:project_name], options[:query_id]

        applog :info, 'Sleep for 60 seconds'
        sleep 60

      end
    end

    desc 'merge PROJECT_NAME QUERY_ID', 'Helper utility to merge branches'

    def merge(project_name, query_id)

      log_block('Merge', 'start')

      applog :info, "Project ID: #{project_name}, Query ID: #{query_id}"

      # Check if there is a current unmerged build branch.
      applog :info, 'Check if there is current build branch'
      regex = /\A\*?\s?build_.*\Z/
      build = `git branch -a`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| regex.match(a) }.last

      build = prepare_build(project_name, build)
      version = Trinity::Redmine::Version.find_version(project_name, build)

      if version.nil?
        applog :warn, 'Version is nil'
        return false
      end

      # Prevent merging to master
      if Trinity::Git.current_branch.match('master')
        applog :warn, 'Current branch is master. STOP MERGING DIRECTLY TO MASTER BRANCH'
        return false
      end

      applog :info, "Current branch is: #{Trinity::Git.current_branch}"

      applog :info, 'Merging master into current branch'
      `git merge master`

      applog :info, 'Begin merging features'

      applog :info, 'Fetching issues and remote branches'
      issues_to_build = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {:project_id => project_name})

      applog :info, "Issues loaded: #{issues_to_build.count.to_s}"

      issues_to_build.each do |issue|

        log_block("Feature #{issue.id} merge", 'start')

        ret = merge_feature_branch(issue, version)
        handle_merge_status(issue, version, ret)

        log_block("Feature #{issue.id} merge", 'end')
        sleep 2
      end

      `git push origin #{build}`

      log_block('Merge', 'end')

      return true
    end

    desc 'rebuild PROJECT_NAME BRANCH_NAME STATUS', 'Helper utility to rebuild build branches'
    method_option :skip_status, :default => false, :type => :boolean, :aliases => '-s', :desc => 'Skip statuses'

    def rebuild(project_name, branch, status = 'open')

      log_block('Rebuild', 'start')

      version = Trinity::Redmine::Version.find_version project_name, branch, status

      if !version.nil?
        applog :info, "Found version: #{version.name} (#{version.id}) [#{version.status}]"
        version_id = version.id.strip.to_i

        applog :info, 'Preparing build branch'

        `git checkout master`
        `git branch -D #{branch}`
        `git push origin :#{branch}` if Trinity::Git.is_branch_pushed(branch)
        `git checkout -b #{branch}`

        issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version_id})
        applog :info, "Loaded issues: #{issues.count.to_s}"

        issues.each do |issue|
          applog :info, "Processing issue: #{issue.id} #{issue.subject}"
          applog :info, "Is status correct (On prerelease - OK)?: #{issue.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok']}"

          correct_status = [
              @config['redmine']['status']['on_prerelease_ok']
          ]

          if correct_status.include?(issue.status.id.to_i) or options[:skip_status]

            applog :info, "Merging issue: #{issue.id} v#{issue.fixed_version.name}"

            ret = merge_feature_branch(issue, version)

            if status.eql? @@merge_statuses[:conflict]
              t = Trinity::Transition.generate('flow_merge_conflict')
              t.config = @config
              t.version = version
              t.handle(issue) if t.check(issue, ret)
            end

            applog :info, ret[:merge_status]
          else
            t = Trinity::Transition.generate('flow_reject_from_build')
            t.config = @config
            t.version = version
            t.handle(issue) if t.check(issue, ret)
          end
        end

        `git push origin #{branch}`

      else
        applog :warn, "Couldn't find version you supplied"
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

      applog :info, "Loaded issues: #{issues.count.to_s}"

      # Check if all issues has right status
      if issues.any? { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }
        applog :info, 'Some issues in the build are in incorrect status'
        issues.select { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }.each do |issue|
          t = Trinity::Transition.generate('flow_reject_from_build')
          t.config = @config
          t.version = version
          t.handle(issue) if t.check(issue, {})
        end
        return @@release_statuses[:need_rebuild]
      elsif issues.count.eql? 0
        applog :warn, 'No issues for build'
        return @@release_statuses[:empty_build]
      else
        applog :info, 'Do not need to rebuild'
        return @@release_statuses[:ok]
      end

      log_block('Release', 'end')
    end

    private

    def handle_merge_status(issue, version, ret)

      case ret[:merge_status]
        when @@merge_statuses[:ok]
          t = Trinity::Transition.generate('flow_merge_ok')
        when @@merge_statuses[:conflict]
          t = Trinity::Transition.generate('flow_merge_conflict')
        else
          t = Trinity::Transition.generate('flow_merge_ok')
      end

      if t.nil?
        applog(:fatal, "Could not generate Transition")
        abort
      end

      t.config = @config
      t.version = version
      t.handle(issue) if t.check(issue, ret)
    end

    def prepare_build(project_name, build)

      log_block('Prepare', 'start')

      ret = {
          :build => nil,
          :version => nil
      }

      applog :info, 'Fetching changes from origin'
      `git fetch origin`
      applog :info, 'Current branch is: %s' % Trinity::Git.current_branch

      # Choosing time for new build branch
      date = choose_date()

      # If there is no current build, create it.
      # Otherwise process current build.
      # Checklist:
      #  * if build pushed & merged, delete build branch and exit the loop
      #  * if build not pushed & not merged, begin merging features
      #  * if build pushed & not merged but it is time to QA - push build and delete local branch

      if build.nil?
        applog :info, 'No current build'
        build_name = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"
        build = Trinity::Git.create_build_branch(date)
        version = Trinity::Redmine.create_version(project_name, build)
        applog :info, "Created new build branch #{build_name}"
        return build
      else
        applog :info, "We have build #{build}"

        version = Trinity::Redmine::Version.find_version(project_name, build)

        if version.nil?
          version = Trinity::Redmine.create_version(project_name, build)
        end

        applog :info, "Found version: #{version.name}"

        if version.nil?
          applog :fatal, 'No version found or loaded'
          abort
        end

        build_pushed = Trinity::Git.is_branch_pushed(build)
        applog :info, "Check if build is pushed to origin: #{build_pushed.inspect}"

        build_merged = Trinity::Git.is_branch_merged(build, 'master')
        applog :info, "Check if build is already merged: #{build_merged.inspect}"

        build_has_no_issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i}).count.eql? 0
        applog :warn, "Build has NO issues: #{build_has_no_issues.inspect}"

        if build_pushed

          applog :info, 'Build pushed to origin'

          if build_merged and build_has_no_issues
            # New empty build
            applog :info, "Build #{build} has no issues. Switching to #{build} and start merging features"
            `git checkout #{build}`
          elsif !build_merged
            # New empty build
            applog :info, "Build #{build} is NOT MERGED to master. Switching to #{build} and start merging features"
            `git checkout #{build}`
          else
            applog :info, "Build #{build} is MERGED to master and PUSHED to origin"

            `git branch -d #{build}`
            applog :info, "Deleted build branch #{build}"

            build = Trinity::Git.create_build_branch(date)
            applog :info, "Created new build branch: #{build}"

            return build
          end

        else
          applog :info, 'Build NOT pushed to origin. Now pushing'
          `git push origin #{build}`
        end

        time_to_qa = time_to_qa(build, options[:hours_to_qa])

        applog :info, "Is it time to QA build?: #{time_to_qa}"

        if time_to_qa
          applog :info, 'Time to QA build.'

          `git push origin #{build}`
          `git checkout master`
          `git branch -D #{build}`

          applog :info, "Deleted branch #{build}"

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

    def merge_feature_branch(issue, version)

      ret = {
          :issue => issue,
          :merge_status => @@merge_statuses[:ok],
          :meta => {}
      }

      related_branch = Trinity::Git.find_issue_related_branch(issue)

      applog :info, "Related branch: #{related_branch}"

      if !related_branch.empty?

        applog :info, 'Merging branch'
        branch_merged = `git branch -r --merged`.split("\n").map { |br| br.strip }.select { |br| related_branch.match(br) }

        if branch_merged.empty?
          applog :info, "Merging #{issue.id} branch #{related_branch}"

          merge_status = `git merge --no-ff #{related_branch}`

          applog :info, merge_status

          conflict = /CONFLICT|fatal/

          if conflict.match(merge_status)
            applog :warn, "Error while automerging branch #{related_branch}"
            applog :info, 'Resetting HEAD'
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
          applog :info, 'Branch already merged. Next...'
        end

      else
        ret[:merge_status] = @@merge_statuses[:empty]
      end

      ret[:issue] = issue

      return ret
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
        applog :error, "#{__method__}: Chronic.parse error"
        abort
      end

      applog :info, "Date for build: #{date}; Hours to QA: #{options[:hours_to_qa]}"
      return date
    end

    def time_to_qa(build, hours_diff)

      applog :info, "Hours diff: #{hours_diff}"
      applog :info, "Build: #{build}"

      # Parse date from build name
      buf = build.split('_').drop(1)
      date_buf = buf.take(3).join('-').concat ' '
      time_buf = buf.last
      date_string = date_buf.concat(time_buf)
      parsed_date = Chronic.parse(date_string)

      if parsed_date.nil?
        applog :fatal, "#{__method__} couldn't parse time"
        abort
      end

      applog :info, "#{__method__}: #{parsed_date}"

      (parsed_date-Time.now)/3600.round <= hours_diff
    end

    def log_block(name, state)
      applog :info, "[============================= #{name}: #{state} ===============================]"
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
        applog(:warn, msg)
      end

      # Notify each contact.
      resolved_contacts.each do |c|
        host = `hostname`.chomp rescue 'none'
        begin
          c.notify(message, Time.now, spec[:priority], spec[:category], host)
          msg = "#{c.info ? c.info : "notification sent for contact: #{c.name}"}"
          applog(:info, msg % [])
        rescue Exception => e
          applog(:error, "#{e.message} #{e.backtrace}")
          msg = "Failed to deliver notification for contact: #{c.name}"
          applog(:error, msg % [])
        end
      end
    end

  end
end