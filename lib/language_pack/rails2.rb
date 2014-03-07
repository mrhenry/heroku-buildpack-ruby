require "fileutils"
require "language_pack"
require "language_pack/rack"
require "shellwords"

# Rails 2 Language Pack. This is for any Rails 2.x apps.
class LanguagePack::Rails2 < LanguagePack::Ruby
  # detects if this is a valid Rails 2 app
  # @return [Boolean] true if it's a Rails 2 app
  def self.use?
    instrument "rails2.use" do
      rails_version = bundler.gem_version('rails')
      return false unless rails_version
      is_rails2 = rails_version >= Gem::Version.new('2.0.0') &&
                  rails_version <  Gem::Version.new('3.0.0')
      return is_rails2
    end
  end

  def name
    "Ruby/Rails"
  end

  def default_config_vars
    instrument "rails2.default_config_vars" do
      super.merge({
        "RAILS_ENV" => "production",
        "RACK_ENV" => "production"
      })
    end
  end

  def default_process_types
    instrument "rails2.default_process_types" do
      super.merge({
        "web" => "http-dispatcher",
        "worker" => "bundle exec rake jobs:work",
        "console" => "bundle exec script/console"
      })
    end
  end

  def default_web_process
    # let's special case thin and puma here if we detect it
    if bundler.has_gem?("thin")
      "bundle exec thin start -e $RACK_ENV -p $PORT"
    else
      "bundle exec ruby script/server -p $PORT"
    end
  end

  def compile
    instrument "rails2.compile" do
      install_plugins
      install_http_dispatcher_config
      super
    end
  end

private

  def install_plugins
    instrument "rails2.install_plugins" do
      plugins = ["rails_log_stdout"].reject { |plugin| bundler.has_gem?(plugin) }
      topic "Rails plugin injection"
      LanguagePack::Helpers::PluginsInstaller.new(plugins).install
    end
  end

  # most rails apps need a database
  # @return [Array] shared database addon
  def add_dev_database_addon
    ['heroku-postgresql:hobby-dev']
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

    app_name = env('APP_NAME') || ''
    env_name = env('RAILS_ENV') || 'production'

    if app_name == ""
      error "APP_NAME environment variable must be set"
    end

    cmd = default_web_process
    cmd = Shellwords.split(cmd)
    cmd = cmd.inspect

    s3_prefix = "/storage/#{app_name}/#{env_name}"
    s3_prefix = s3_prefix.inspect

    config = <<-CONFIG
[
  { "type": "fs", "match": "/", "path": "public"},
  { "type": "aws-s3", "bucket": "lalala-assets", "match": "/storage", "prefix": #{s3_prefix} },
  { "type": "proc", "args": #{cmd} }
]
CONFIG

    File.open(".http-dispatcher.json", "w+", 0644) do |f|
      f.write config
    end

    topic "Using default http-dispatcher config"
    true
  end

end

