require "fileutils"
require "language_pack"
require "language_pack/rack"
require "shellwords"

# Rails 2 Language Pack. This is for any Rails 2.x apps.
class LanguagePack::Rails2 < LanguagePack::Ruby

  # detects if this is a valid Rails 2 app
  # @return [Boolean] true if it's a Rails 2 app
  def self.use?
    if gemfile_lock?
      rails_version = LanguagePack::Ruby.gem_version('rails')
      rails_version >= Gem::Version.new('2.0.0') && rails_version < Gem::Version.new('3.0.0') if rails_version
    end
  end

  def name
    "Ruby/Rails"
  end

  def default_config_vars
    super.merge({
      "RAILS_ENV" => "production",
      "RACK_ENV" => "production"
    })
  end

  def default_process_types
    super.merge({
      "web" => "http-dispatcher",
      "worker" => "bundle exec rake jobs:work",
      "console" => "bundle exec script/console"
    })
  end

  def default_web_process
    # let's special case thin and puma here if we detect it
    if gem_is_bundled?("thin")
      "bundle exec thin start -e $RACK_ENV -S $SOCK"
    elsif gem_is_bundled?("puma")
      "bundle exec puma -b unix://$SOCK"
    else
      "bundle exec ruby script/server -p $PORT"
    end
  end

  def compile
    super
    install_plugins
    migrate_db
    install_http_dispatcher_config
  end

private

  # list of plugins to be installed
  # @return [Array] resulting list in a String Array
  def plugins
    %w( rails_log_stdout )
  end

  # the root path of where the plugins are to be installed from
  # @return [String] the resulting path
  def plugin_root
    File.expand_path("../../../vendor/plugins", __FILE__)
  end

  # vendors all the plugins into the slug
  def install_plugins
    topic "Rails plugin injection"
    plugins.each { |plugin| install_plugin(plugin) }
  end

  # vendors an individual plugin
  # @param [String] name of the plugin
  def install_plugin(name)
    plugin_dir = "vendor/plugins/#{name}"
    return if File.exist?(plugin_dir)
    puts "Injecting #{name}"
    FileUtils.mkdir_p plugin_dir
    Dir.chdir(plugin_dir) do |dir|
      run("curl #{VENDOR_URL}/#{name}.tgz -s -o - | tar xzf -")
    end
  end

  # most rails apps need a database
  # @return [Array] shared database addon
  def add_dev_database_addon
    ['heroku-postgresql:dev']
  end

  # sets up the profile.d script for this buildpack
  def setup_profiled
    super
    set_env_default "RACK_ENV",  "production"
    set_env_default "RAILS_ENV", "production"
  end

  def install_http_dispatcher_config
    if File.exists?('.http-dispatcher.json')
      topic "Using custom http-dispatcher config: .http-dispatcher.json"
      return true
    end

    app_name = ENV['APP_NAME'] || ''
    env_name = ENV['RAILS_ENV'] || 'production'

    if app_name == ""
      error "APP_NAME environment variable must be set"
    end

    cmd = default_web_process
    cmd = Shellwords.split(cmd)
    cmd = cmd.inspect

    s3_prefix = "/storage/#{app_name}/#{env_name}/assets"
    s3_prefix = s3_prefix.inspect

    config = <<-CONFIG
[
  { "type": "fs", "match": "/", "path": "public"},
  { "type": "aws-s3", "bucket": "lalala-assets", "match": "/storage/assets", "prefix": #{s3_prefix} },
  { "type": "proc", "args": #{cmd} }
]
CONFIG

    File.open(".http-dispatcher.json", "w+", 0644) do |f|
      f.write config
    end

    topic "Using default http-dispatcher config"
    true
  end

  def migrate_db
    log("db_migrate") do

      puts "Running: rake db:migrate"
      require 'benchmark'
      time = Benchmark.realtime { pipe("env PATH=$PATH:bin bundle exec rake db:migrate 2>&1") }

      if $?.success?
	log "assets_precompile", :status => "success"
	puts "Database migration completed (#{"%.2f" % time}s)"
      else
	log "assets_precompile", :status => "failure"
	error "Failed to migrate the database"
      end

    end
  end

end

