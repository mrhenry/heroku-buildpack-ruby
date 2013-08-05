require "language_pack"
require "language_pack/ruby"

# Rack Language Pack. This is for any non-Rails Rack apps like Sinatra.
class LanguagePack::Rack < LanguagePack::Ruby

  # detects if this is a valid Rack app by seeing if "config.ru" exists
  # @return [Boolean] true if it's a Rack app
  def self.use?
    instrument "rack.use" do
      gemfile_lock? && LanguagePack::Ruby.gem_version('rack')
    end
  end

  def name
    "Ruby/Rack"
  end

  def default_config_vars
    instrument "rack.default_config_vars" do
      super.merge({
        "RACK_ENV" => "production"
      })
    end
  end

  def default_process_types
    super.merge({
      "web" => "http-dispatcher"
    })
  end

  def default_web_process
    # let's special case thin and puma here if we detect it
    if gem_is_bundled?("thin")
      "bundle exec thin start -R config.ru -e $RACK_ENV -p $PORT"
    elsif gem_is_bundled?("puma")
      "bundle exec puma -b tcp://0.0.0.0:$PORT"
    else
      "bundle exec rackup config.ru -p $PORT"
    end
  end

private

  # sets up the profile.d script for this buildpack
  def setup_profiled
    super
    set_env_default "RACK_ENV", "production"
  end

end

