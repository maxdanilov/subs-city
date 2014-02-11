module Subscity
  class App < Padrino::Application
    use ActiveRecord::ConnectionAdapters::ConnectionManagement
    register Padrino::Rendering
    register Padrino::Mailer
    register Padrino::Helpers

    enable :sessions

    ##
    # Caching support.
    #
    # register Padrino::Cache
    # enable :caching
    #
    # You can customize caching store engines:
    #
    # set :cache, Padrino::Cache::Store::Memcache.new(::Memcached.new('127.0.0.1:11211', :exception_retry_limit => 1))
    # set :cache, Padrino::Cache::Store::Memcache.new(::Dalli::Client.new('127.0.0.1:11211', :exception_retry_limit => 1))
    # set :cache, Padrino::Cache::Store::Redis.new(::Redis.new(:host => '127.0.0.1', :port => 6379, :db => 0))
    # set :cache, Padrino::Cache::Store::Memory.new(50)
    # set :cache, Padrino::Cache::Store::File.new(Padrino.root('tmp', app_name.to_s, 'cache')) # default choice
    #

    ##
    # Application configuration options.
    #
    # set :raise_errors, true       # Raise exceptions (will stop application) (default for test)
    # set :dump_errors, true        # Exception backtraces are written to STDERR (default for production/development)
    # set :show_exceptions, true    # Shows a stack trace in browser (default for development)
    # set :logging, true            # Logging in STDOUT for development and file for production (default only for development)
    # set :public_folder, 'foo/bar' # Location for static assets (default root/public)
    # set :reload, false            # Reload application files (default in development)
    # set :default_builder, 'foo'   # Set a custom form builder (default 'StandardFormBuilder')
    # set :locale_path, 'bar'       # Set path for I18n translations (default your_apps_root_path/locale)
    # disable :sessions             # Disabled sessions by default (enable if needed)
    # disable :flash                # Disables sinatra-flash (enabled by default if Sinatra::Flash is defined)
    # layout  :my_layout            # Layout can be in views/layouts/foo.ext or views/foo.ext (default :application)
    #

    ##
    # You can configure for a specified environment like:
    #
    #   configure :development do
    #     set :foo, :bar
    #     disable :asset_stamp # no asset timestamping for dev
    #   end
    #

    ##
    # You can manage errors like:
    #
    #   error 404 do
    #     render 'errors/404'
    #   end
    #
    #   error 505 do
    #     render 'errors/505'
    #   end
    #
	
	get '/' do
		#source = File.read("cinemas0.txt") #KassaFetcher.get_movies_list
		#source = KassaFetcher.fetch_data(KassaFetcher.url_for_cinemas(0))
		#Logger.put( data )
	end
	
	get '/update/cinemas' do
		fetched, updated = Cinema.update_all
        "fetched #{fetched}, updated #{updated} records..."
	end

    get '/update/movies' do
        fetched, updated = Movie.update_all
        "fetched #{fetched}, updated #{updated} records..."
    end

    get '/cinemas' do
        @cinemas = Cinema.all(:order => 'created_at desc')
        render 'cinema/showall'
    end
=begin	
    get '/update/sessions' do
        url = KassaFetcher.url_for_sessions(Movie.first.movie_id, Time.now + 86400)
        Logger.put (url)
        Logger.put (KassaFetcher.fetch_data_html(url))
    end
=end
    get '/update/screenings' do
        updated = 0
        (0..7).each do |day| 
            updated += Screening.update(Movie.first.movie_id, Time.now + 86400*day, 2)
            #updated += Screening.update(54672, Time.now + 86400*day, 2)
        end
        "Updated #{updated} records..."
    end

  end
end
