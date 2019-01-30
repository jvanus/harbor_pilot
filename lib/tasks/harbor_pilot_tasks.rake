DOCKER_PATH = File.expand_path('../../../files', __FILE__)
CONFIG = HarborPilot.configuration.for(Rails.env)

def database_exists?
  ActiveRecord::Base.connection
rescue ActiveRecord::NoDatabaseError
  false
else
  true
end

##
# -e APP_REGISTRY_PATH -e SERVICE_NAME etc
# VERSION is removed because it has special meaning to rails (migrations)
def env_for_docker_run
  CONFIG.shell_env.keys.reject{|k| k == "VERSION" }.map{|key| "-e #{key}" }.join(" ")
end

def move_arrays(array)
  cols = []
  array.each_with_index do |inner_array, index|
    cols[index] = inner_array[index]
  end
  cols
end

def print_in_columns(array)
  array.each_with_index do |row, row_number|
    row.each_with_index do |cell, col_number|
      col_size = array.map{|a| a[col_number] || "" }.map(&:length).max + 1
      print cell.ljust(col_size)
    end
    print "\n"
  end
end

def filter_secrets(hash)
  filtered = hash.map do |key, value|
    if CONFIG.secrets_to_filter.include? key
      [key, "[REDACTED]"]
    else
      [key, value]
    end
  end
  filtered
end

def print_and_run(cmd)
  # stop_if_key_missing  # TODO: move this maybe

  unless @have_printed_env_before
    puts "\nEnvironment:"
    print_in_columns filter_secrets(CONFIG.env)
    @have_printed_env_before = true
  end

  puts "\nCommand:"
  puts cmd
  puts "\n\n"
  system(CONFIG.shell_env, cmd)
end

def docker_config
  @docker_config ||= JSON.parse File.read(CONFIG.docker_user_config_path)
rescue Errno::ENOENT # => No such file or directory
  return nil
end

def docker_command_string
  "docker -H ssh://#{CONFIG.manager_user}@#{CONFIG.manager_node}"
end

def stop_if_key_missing
  raise "Can not run without a RAILS_MASTER_KEY" if CONFIG.rails_master_key.blank?
end

def remove_server_pid
  "/app/tmp/pids/server.pid"
end

def wait_for_db_to_start
  seconds_to_wait = 120
  seconds_elapsed = 0
  seconds_per_try = 5
  begin
    ActiveRecord::Base.connection
  rescue OCIError => e
    # TODO: OCIError is oracle specific, Add support for other DBs
    if seconds_elapsed == 0
      print "Database hasn't started yet. Waiting upto #{seconds_to_wait} seconds."
    end

    if seconds_elapsed < seconds_to_wait
      sleep seconds_per_try
      seconds_elapsed += seconds_per_try
      print '.'
      retry
    end

    if seconds_elapsed == seconds_to_wait
      puts e.full_message
      puts <<~HEREDOC

      ************************
      The Database failed to start within the alotted time, shutting down.
      See above for last error.
      ************************

      HEREDOC
      exit
    end
  end
end

##
# This is a workaround.
# By default, Docker only copies data from a container into a named volume
# if the volume is empty when the container starts. This behavour
# prevents static assets from being updated on subsiquent deploys.
# By mounting the public volume in a different path in the stack file, 
# we can manually copy data from our app container into the volume when it 
# starts. 
def copy_public
  if Dir.exists?("/volumes/public")
    FileUtils.cp_r "/app/public/.", "/volumes/public"
  end
end


desc "Setup the DB if necessary, run migrations, and start the server"
task start: :environment do
  wait_for_db_to_start
  copy_public

  unless database_exists?
    puts "\n== Creating the database =="
    Rake::Task["db:setup"].invoke
  end

  puts "\n== Migrating the database =="
  Rake::Task["db:migrate"].invoke

  puts "\n== Starting application server =="
  `bin/rails server -b 0.0.0.0`
end 

##
# Returns the correct path to a file used by docker
# ie: Dockerfile, docker-compose.yml, docker-stack.yml
def dockerfile(filename="Dockerfile")
  if File.exists?(filename)
    filename
  else
    [DOCKER_PATH, filename].join File::SEPARATOR
  end
end

namespace :docker do
  desc "Build the docker image"
  task build: :environment do
    cmd = <<~HEREDOC
      docker login #{CONFIG.registry_path}
      DOCKER_BUILDKIT=1 docker build --ssh=default \
      --build-arg RAILS_MASTER_KEY=#{CONFIG.rails_master_key} \
      -t #{CONFIG.app_registry_path}:latest \
      -t #{CONFIG.app_registry_path}:#{CONFIG.version} \
      -f #{dockerfile} .
    HEREDOC
    print_and_run(cmd)
  end

  desc "Execute a command within the docker image"
  task :exec, [:command, :deployment_version] => :environment do |t, args|
    args.with_defaults command: "bash"
    CONFIG.version = args[:deployment_version] if args[:deployment_version]

    puts "getting a console for #{CONFIG.app_registry_path}..."
    print_and_run("docker run -it #{env_for_docker_run} #{CONFIG.app_registry_path}:#{CONFIG.version} #{args[:command]}")
  end

  desc "Run the server from the docker image"
  task :server, [:deployment_version] => :environment do |t, args|
    CONFIG.version = args[:deployment_version] if args[:deployment_version]

    puts "running a server for #{CONFIG.app_registry_path}..."
    print_and_run("docker run -p 3000:3000 #{env_for_docker_run} #{CONFIG.app_registry_path}:#{CONFIG.version}")
  end

  desc "Push the docker image to the repo"
  task push: :environment do
    puts "pushing #{CONFIG.app_registry_path}..."
    print_and_run("docker login #{CONFIG.registry_path}")
    print_and_run("docker push #{CONFIG.app_registry_path}:latest")
    print_and_run("docker push #{CONFIG.app_registry_path}:#{CONFIG.version}")
  end

  desc "Deploy the app to $RAILS_ENV"
  task :deploy, [:deployment_version] => :environment do |t, args|
    CONFIG.version = args[:deployment_version] if args[:deployment_version]

    puts "deploying #{CONFIG.app_name}:#{CONFIG.version} to #{Rails.env}..."
    cmd  = "#{docker_command_string} login #{CONFIG.registry_path} && "
    cmd += "#{docker_command_string} pull #{CONFIG.app_registry_path}:#{CONFIG.version} && "
    cmd += "#{docker_command_string} stack deploy #{CONFIG.app_name} -c #{dockerfile('docker-stack.yml')} --resolve-image=always --with-registry-auth"
    # need to determine if docker service is already running, otherwise issue and update request
    # (docker service update --quiet --detach=true --update-delay 15s #{CONFIG.app_name} &) > /dev/null 2>&1
    print_and_run(cmd)
  end
end
