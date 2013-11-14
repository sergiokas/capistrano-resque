require "capistrano/version"

namespace :resque do

  ## Helper functions
  def workers_roles
    return workers.keys if workers.first[1].is_a? Hash
    [:resque_worker]
  end

  def for_each_workers(&block)
    if workers.first[1].is_a? Hash
      workers_roles.each do |role|
        yield(role.to_sym, workers[role.to_sym])
      end
    else
      yield(:resque_worker,workers)
    end
  end

  def status_command
    "if [ -e #{current_path}/tmp/pids/resque_work_1.pid ]; then \
      for f in $(ls #{current_path}/tmp/pids/resque_work*.pid); \
        do ps -p $(cat $f) | sed -n 2p ; done \
     ;fi"
  end

  def start_command(queue, pid)
    "cd #{current_path} && RAILS_ENV=#{rails_env} QUEUE=\"#{queue}\" \
     PIDFILE=#{pid} BACKGROUND=yes VERBOSE=1 INTERVAL=#{interval} \
     #{fetch(:bundle_cmd, "bundle")} exec rake resque:work"
  end

  def stop_command
    "if [ -e #{current_path}/tmp/pids/resque_work_1.pid ]; then \
     for f in `ls #{current_path}/tmp/pids/resque_work*.pid`; \
       do #{try_sudo} kill -s #{resque_kill_signal} `cat $f` \
       && rm $f ;done \
     ;fi"
  end

  def start_scheduler(pid)
    "cd #{current_path} && RAILS_ENV=#{rails_env} \
     PIDFILE=#{pid} BACKGROUND=yes VERBOSE=1 MUTE=1 \
     #{fetch(:bundle_cmd, "bundle")} exec rake resque:scheduler"
  end

  def stop_scheduler(pid)
    "if [ -e #{pid} ]; then \
      #{try_sudo} kill $(cat #{pid}) ; rm #{pid} \
     ;fi"
  end

  desc "See current worker status"
  task :status do
    on roles(lambda { workers_roles() }), :on_no_matching_servers => :continue do
      run(status_command)
    end
  end

  desc "Start Resque workers"
  task :start do
    on roles(lambda { workers_roles() }), :on_no_matching_servers => :continue do
      for_each_workers do |role, workers|
        worker_id = 1
        workers.each_pair do |queue, number_of_workers|
          logger.info "Starting #{number_of_workers} worker(s) with QUEUE: #{queue}"
          threads = []
          number_of_workers.times do
            pid = "./tmp/pids/resque_work_#{worker_id}.pid"
            threads << Thread.new(pid) { |pid| run(start_command(queue, pid), :roles => role) }
            worker_id += 1
          end
          threads.each(&:join)
        end
      end
    end
  end

  # See https://github.com/defunkt/resque#signals for a descriptions of signals
  # QUIT - Wait for child to finish processing then exit (graceful)
  # TERM / INT - Immediately kill child then exit (stale or stuck)
  # USR1 - Immediately kill child but don't exit (stale or stuck)
  # USR2 - Don't start to process any new jobs (pause)
  # CONT - Start to process new jobs again after a USR2 (resume)
  desc "Quit running Resque workers"
  task :stop do
    on roles(lambda { workers_roles() }), :on_no_matching_servers => :continue do
      run(stop_command)
    end
  end

  desc "Restart running Resque workers"
  task :restart do
    on roles(lambda { workers_roles() }), :on_no_matching_servers => :continue do
      stop
      start
    end
  end

  namespace :scheduler do
    desc "Starts resque scheduler with default configs"
    task :start do
      on roles(:resque_scheduler) do
        pid = "#{current_path}/tmp/pids/scheduler.pid"
        run(start_scheduler(pid))
      end
    end

    desc "Stops resque scheduler"
    task :stop do
      on roles(:resque_scheduler) do
        pid = "#{current_path}/tmp/pids/scheduler.pid"
        run(stop_scheduler(pid))
      end
    end

    task :restart do
      stop
      start
    end
  end
end



#   desc <<-DESC
#         Install the current Bundler environment. By default, gems will be \
#         installed to the shared/bundle path. Gems in the development and \
#         test group will not be installed. The install command is executed \
#         with the --deployment and --quiet flags.

#         You can override any of these defaults by setting the variables shown below.

#           set :bundle_gemfile, -> { release_path.join('Gemfile') }
#           set :bundle_dir, -> { shared_path.join('bundle') }
#           set :bundle_flags, '--deployment --quiet'
#           set :bundle_without, %w{development test}.join(' ')
#           set :bundle_binstubs, -> { shared_path.join('bin') }
#           set :bundle_roles, :all
#     DESC
#   task :install do
#     on roles fetch(:bundle_roles) do
#       within release_path do
#         execute :bundle, "--gemfile #{fetch(:bundle_gemfile)}",
#           "--path #{fetch(:bundle_dir)}",
#           fetch(:bundle_flags),
#           "--binstubs #{fetch(:bundle_binstubs)}",
#           "--without #{fetch(:bundle_without)}"
#       end
#     end
#   end

#   before 'deploy:updated', 'bundler:install'
# end

# namespace :load do
#   task :defaults do
#     set :bundle_gemfile, -> { release_path.join('Gemfile') }
#     set :bundle_dir, -> { shared_path.join('bundle') }
#     set :bundle_flags, '--deployment --quiet'
#     set :bundle_without, %w{development test}.join(' ')
#     set :bundle_binstubs, -> { shared_path.join('bin') }
#     set :bundle_roles, :all
#   end
# end

# module CapistranoResque
#   class CapistranoIntegration
#     def self.load_into(capistrano_config)
#       capistrano_config.load do

#         _cset(:workers, {"*" => 1})
#         _cset(:resque_kill_signal, "QUIT")
#         _cset(:interval, "5")

#         namespace :resque do
#           desc "See current worker status"
#           task :status, :roles => lambda { workers_roles() }, :on_no_matching_servers => :continue do
#             run(status_command)
#           end

#           desc "Start Resque workers"
#           task :start, :roles => lambda { workers_roles() }, :on_no_matching_servers => :continue do
#             for_each_workers do |role, workers|
#               worker_id = 1
#               workers.each_pair do |queue, number_of_workers|
#                 logger.info "Starting #{number_of_workers} worker(s) with QUEUE: #{queue}"
#                 threads = []
#                 number_of_workers.times do
#                   pid = "./tmp/pids/resque_work_#{worker_id}.pid"
#                   threads << Thread.new(pid) { |pid| run(start_command(queue, pid), :roles => role) }
#                   worker_id += 1
#                 end
#                 threads.each(&:join)
#               end
#             end
#           end

#           # See https://github.com/defunkt/resque#signals for a descriptions of signals
#           # QUIT - Wait for child to finish processing then exit (graceful)
#           # TERM / INT - Immediately kill child then exit (stale or stuck)
#           # USR1 - Immediately kill child but don't exit (stale or stuck)
#           # USR2 - Don't start to process any new jobs (pause)
#           # CONT - Start to process new jobs again after a USR2 (resume)
#           desc "Quit running Resque workers"
#           task :stop, :roles => lambda { workers_roles() }, :on_no_matching_servers => :continue do
#             run(stop_command)
#           end

#           desc "Restart running Resque workers"
#           task :restart, :roles => lambda { workers_roles() }, :on_no_matching_servers => :continue do
#             stop
#             start
#           end

#           namespace :scheduler do
#             desc "Starts resque scheduler with default configs"
#             task :start, :roles => :resque_scheduler do
#               pid = "#{current_path}/tmp/pids/scheduler.pid"
#               run(start_scheduler(pid))
#             end

#             desc "Stops resque scheduler"
#             task :stop, :roles => :resque_scheduler do
#               pid = "#{current_path}/tmp/pids/scheduler.pid"
#               run(stop_scheduler(pid))
#             end

#             task :restart do
#               stop
#               start
#             end
#           end
#         end
#       end
#     end
#   end
# end

# # if Capistrano::Configuration.instance
# #   CapistranoResque::CapistranoIntegration.load_into(Capistrano::Configuration.instance)
# # end
