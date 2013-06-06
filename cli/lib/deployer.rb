require 'rest-client'
require 'json'
require 'base64'
require 'parallel'
require 'net/ssh'

module OpenShift
  module Deployment
    module CLI
      class Deployer
        #TODO see if there's an easy way to avoid duplicating these
        #in gear/lib/deployment.rb
        USER_DIR_NAME = "app-root/runtime/user"
        USER_DIR = "#{ENV['OPENSHIFT_HOMEDIR']}/#{USER_DIR_NAME}"

        ARTIFACTS_DIR = "#{USER_DIR}/artifacts"
        ARTIFACTS_DIR_NAME = "#{USER_DIR_NAME}/artifacts"

        DEPLOYMENTS_DIR = "#{USER_DIR}/deployments"
        DEPLOYMENTS_DIR_NAME = "#{USER_DIR_NAME}/deployments"

        SCRIPTS_DIR = "#{USER_DIR}/scripts"
        SCRIPTS_DIR_NAME = "#{USER_DIR_NAME}/scripts"

        def initialize(args, options)
          @user = options.user || $default_user
          @password = options.password
          @token = nil
          @server = options.server || $default_server
          @args = args
          @options = options
          @app_name = @args.shift

          raise "Missing credentials" unless (@user and @password) or token
        end

        def init_head_gear
          output = parallel(gears) do |gear|
            result = []
            ssh_url = gear['ssh_url'].gsub(/^ssh:\/\//, '')

            result << "Creating directories"
            `ssh #{ssh_url} mkdir -p #{ARTIFACTS_DIR_NAME}`
            `ssh #{ssh_url} mkdir -p #{DEPLOYMENTS_DIR_NAME}`
            `ssh #{ssh_url} mkdir -p #{SCRIPTS_DIR_NAME}`

            result << 'Syncing scripts'
            result << `rsync -axvz --exclude user_prepare #{File.dirname(__FILE__)}/../../gear/ #{ssh_url}:#{SCRIPTS_DIR_NAME}/`
          end

          gears.collect {|g| g['id']}.each_with_index do |gear_id, index|
            color "Result from gear #{gear_id}", :bold, :underline
            say output[index].join("\n")
            say "\n"
          end

          color "Initializing bundle", :bold, :underline
          say `ssh #{app_ssh_string} "cd #{SCRIPTS_DIR_NAME} && bundle install --local --deployment"`
        end

        def status
          say "Application #{@app_name} has #{gears.count} gears:"

          output = parallel(gears) do |gear|
            ssh_url = gear['ssh_url'].gsub(/^ssh:\/\//, '')
            version = `ssh #{ssh_url} '#{SCRIPTS_DIR_NAME}/show-version 2>&1'`
            version = "Error checking version: #{output}" unless $?.success?
            {:ssh_url => gear['ssh_url'], :version => version, :state => gear['state']}
          end

          gears.collect {|g| g['id']}.each_with_index do |gear_id, index|
            color "Gear #{gear_id}", :bold, :underline
            result = output[index]
            say "  SSH URL: #{result[:ssh_url]}"
            say "  Deployed version: #{result[:version]}"
            say "  State: #{result[:state]}"
            say "\n"
          end
        end

        def prepare
          say `ssh #{app_ssh_string} "#{SCRIPTS_DIR_NAME}/prepare #{@args.join(' ')}"`
        end

        def distribute
          say `ssh #{app_ssh_string} "cd #{SCRIPTS_DIR_NAME} && ./distribute #{@args.join(' ')}"`
        end

        def artifacts
          output = parallel(gears) do |gear|
            ssh_url = gear['ssh_url'].gsub(/^ssh:\/\//, '')
            `ssh #{ssh_url} "#{SCRIPTS_DIR_NAME}/artifacts"`
          end

          gears.collect {|g| g['id']}.each_with_index do |gear_id, index|
            color "Gear #{gear_id}", :bold, :underline
            artifacts = output[index].split("\n")
            artifacts.each { |r| say "  #{r}" }
            say "\n"
          end
        end

        def deployments
          output = parallel(gears) do |gear|
            ssh_url = gear['ssh_url'].gsub(/^ssh:\/\//, '')
            `ssh #{ssh_url} "#{SCRIPTS_DIR_NAME}/deployments"`
          end

          gears.collect {|g| g['id']}.each_with_index do |gear_id, index|
            color "Gear #{gear_id}", :bold, :underline
            artifacts = output[index].split("\n")
            artifacts.each { |r| say "  #{r}" }
            say "\n"
          end
        end

        def activate(action='activate')
          if @options.gears
            targets = File.readlines(@options.gears).map(&:chomp)
          else
            targets = gears.collect { |g| g['ssh_url'] }
          end

          ok = []
          bad = []

          output = parallel(targets) do |ssh_url|
            ssh_url.gsub!(/^ssh:\/\//, '')
            uuid = ssh_url.split('@')[0]

            if @options.dry_run
              `ssh #{ssh_url} "#{SCRIPTS_DIR_NAME}/can_#{action} #{@args[0]}"`
              if $?.success?
                ok << uuid
              else
                bad << uuid
              end
            else
              `ssh #{ssh_url} "#{SCRIPTS_DIR_NAME}/#{action} #{@args.join(' ')} 2>&1"`
            end
          end

          if @options.dry_run
            color "Gears that should #{action} successfully:", :bold, :underline
            ok.each { |g| say g }
            say "\n"
            color "Gears that will not #{action} successfully:", :bold, :underline
            bad.each { |g| say g }
          else
            targets.collect { |t| t.gsub(/^ssh:\/\//, '').split('@')[0] }.each_with_index do |uuid, index|
              color "Result from #{uuid}:", :bold, :underline
              output[index].each { |o| say "  #{o}" }
            end
          end
        end

        def rollback
          activate('rollback')
        end

        def partition
          raise "You cannot specify both --percents and --counts" if @options.counts and @options.percents

          partitions = []

          if @options.counts
            sum = @options.counts.map(&:to_i).inject(:+)
            raise "Total number of gears specified by --counts (#{sum}) exceeds actual number of gears (#{gears.count})" if sum > gears.count

            start = 0
            used = 0
            @options.counts.map(&:to_i).each do |count|
              #TODO randomize
              partition = gears[start, count]
              start += count
              used += count
              partitions << partition
            end


            if used < gears.count
              partition = gears[start..-1]
              partitions << partition
            end

            partitions.each_with_index do |partition, index|
              FileUtils.mkdir_p(@options.output_dir)
              File.open(File.join(@options.output_dir, "#{@app_name}-#{index+1}-#{partitions.count}"), 'w') do |file|
                partition.each do |gear|
                  file.puts gear['ssh_url']
                end
              end
            end
          else
=begin
            # percents
            start = 0
            used = 0
            partitions = []
            filenames = []
            @options.percents.map(&:to_i).each do |percent|
              count = gears.count * percent / 100
              if count < 1
                raise "Unable to select #{percent}% of #{gears.count} gears - would be less than 1"
              end

              partition = gears[start, count]
              start += count
              used += count
              partitions << partition
              filenames << percent
            end

            if used < gears.count
              partition = gears[start..-1]
              partitions << partition
              filenames << 100 * (gears.count - used) / gears.count
            end

            partitions.each_with_index do |partition, index|
              FileUtils.mkdir_p(@options.output_dir)
              File.open(File.join(@options.output_dir, "#{@app_name}-#{filenames[index]}pct"), 'w') do |file|
                partition.each do |gear|
                  file.puts gear['id']
                end
              end
            end
=end
          end
        end

      private

        def token_key
          "#{@user}@#{@server}"
        end

        def token_filename
          "token_#{Base64.encode64(Digest::MD5.digest(token_key)).gsub(/[^\w\@]/, '')}"
        end

        def token_file
          File.join(File.expand_path('~/.openshift'), token_filename)
        end

        def token
          # only look up the token if no password was specified, we haven't
          # looked it up before, and the token file exists
          if !@password and !@token and File.exist?(token_file)
            @token = IO.read(token_file)
            @token = @token.strip.gsub(/[\n\r\t]/, '')
          end

          @token
        end

        def get(path)
          headers = {:accept => :json}
          if token
            auth = ''
            headers['Authorization'] = "Bearer #{token}"
          else
            auth = "#{@user}:#{@password}@"
          end

          json = RestClient.get("https://#{auth}#{@server}/broker/rest#{path}", headers)
          JSON.parse(json)
        end

        def domain
          @domain ||= get('/domains')['data'][0]['id']
        end

        def app
          @app ||= get("/domains/#{domain}/applications/#{@app_name}")
        end

        def gears
          gear_groups ||= get("/domains/#{domain}/applications/#{@app_name}/gear_groups")['data']
          # e.g. ruby-1.9
          framework = app['data']['framework']

          result = []

          gear_groups.each do |gear_group|
            gear_group['cartridges'].each do |cartridge|
              if cartridge['name'] == framework
                result += gear_group['gears']
              end
            end
          end

          result
        end

        def app_ssh_string
          @app_ssh_string ||= app['data']['ssh_url'].gsub('ssh://','')
        end

        def app_ssh_user_host
          @app_ssh_user_host ||= app_ssh_string.split('@')
        end

        def parallel(array, &block)
          Parallel.map(array, :in_threads => 5 || @options.threads, &block)
        end

      end
    end
  end
end
