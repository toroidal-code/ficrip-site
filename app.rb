require 'sinatra/base'
require 'newrelic_rpm'
require 'padrino-helpers'
require 'rufus-scheduler'
require 'concurrent'
require 'hamster/hash'

require 'haml'
require 'slim'
require 'oj_mimic_json'
require 'ficrip'

$files = Concurrent::Hash.new

# Cleanup old files by checking to see
# if they're older than 6 hours
def cleanup_old_files
  $files.each_key do |id|
    if (Time.now - (6 * 60 * 60)) > $files[id][:time]
      $files[id][:tempfile].close
      $files[id][:tempfile].unlink
      $files.delete k
    end
  end
rescue => e
  p e
end

# Every two hours, clean up the leftover tempfiles that
# haven't already been GC'ed
if $scheduler_thread
  scheduler = Rufus::Scheduler.new
  scheduler.every '2h' do
    cleanup_old_files
  end
end

# This is a simple little helper
# module for properly formatting
# Server-Sent Event messages
module SSE
  def self.data(obj)
    "data: #{obj}\n\n"
  end

  def self.event(ev, obj)
    s = String.new
    s << "event: #{ev}\n"
    s << "data: #{obj}\n\n"
  end
end

# The core of the web application
class Application < Sinatra::Base
  register Padrino::Helpers

  configure do
    enable :sessions
    set :session_secret, SecureRandom.hex(32)
    enable :protection
    # enable authenticity_token in forms
    set :protect_from_csrf, true
    # actual checks for csrf tokens from form submissions
    use Rack::Protection, except: :http_origin

    set :server, :puma
  end

  # The source-to-source transformations to switch themes
  replacements = [/(white|black|waves-light|light|dark)/,
                  { 'white'       => 'black', 'black' => 'white',
                    'light'       => 'dark', 'dark' => 'light',
                    'waves-light' => '' }]

  # The index page
  get '/' do
    html = render 'index', layout: :main
    [true, false].sample ? html.gsub(*replacements) : html
  end

  # Light theme
  get '/light' do
    render 'index', layout: :main
  end

  # Dark theme
  get '/dark' do
    render('index', layout: :main).gsub(*replacements)
  end

  # Get a fanfic.
  # Takes two query params: 'style' and 'url'
  # 'url' is, obviously, the fanfiction.net story's URL
  get '/get' do
    halt 403, render('errors/403') unless params[:url]
    html = render 'download', layout: :main
    params[:style] == 'dark' ? html.gsub(*replacements) : html
  end

  # Regexp to extract ff.net storyid from the URL
  storyid_regexp = Regexp.new('fanfiction.net/s/(\d+)', true)

  # The real guts of the fetcher
  get '/generate', provides: 'text/event-stream' do
    halt 403, render('errors/403') unless params[:url] && params[:clientId]

    id  = params[:clientId]
    url = params[:url]

    stream do |out|
      storyid = begin
        Integer url.match(storyid_regexp)[1]
      rescue
        out << SSE.event(:error, "Error! \"#{url}\" isn't a valid story URL."); nil
      end

      fic = begin
        Ficrip.fetch storyid
      rescue
        out << SSE.event(:error, "Error! There's no fic with id #{storyid}."); nil
      end if storyid

      begin
        # Update the download page with title/author information
        out << SSE.event(:info, {
            title:  link_to(fic.title, fic.url),
            author: link_to(fic.author, fic.author_url)
        }.to_json)

        # Process the story into an EPUB2, incrementing the progressbar
        epub = fic.bind version: 2, callback: lambda { |fetched, total|
          percent = (fetched / total.to_f) * 100
          out << SSE.event(:progress, "#{percent.to_i}%")
          sleep 0.5 # poor man's rate limiter
        }

        # Switch to the indeterminate progressbar
        out << SSE.event(:progress, "null")

        filename = "#{fic.author} - #{fic.title}.epub"
        temp     = Tempfile.new filename

        # Write the epub to the tempfile
        epub.generate_epub_stream.tap do |es|
          es.rewind
          temp.write es.read
          es.close
        end

        $files[id] = Hamster::Hash[filename: filename, tempfile: temp, time: Time.now]

        # Encode the file information into a query string
        query = URI.encode_www_form([[:filename, filename],
                                     [:path, temp.path], [:id, id]])


        out << SSE.event(:progress, "100%")      # We're done, so set progress to 100%
        out << SSE.event(:url, "/file?#{query}") # And give the client the file link
      rescue Exception => ex
        puts "An error of type #{ex.class} happened, message is #{ex.message}"
      end if fic
      out << SSE.event(:close, true)
    end
  end

  # Download the generated file
  get '/file' do
    halt 403, render('errors/403') unless params[:path] && params[:id] && params[:filename]
    id = params[:id]

    begin
      send_file params[:path], filename: params[:filename], type: 'application/epub+zip'
    ensure
      unless (file = $files[id]).nil?
        file[:tempfile].close
        file[:tempfile].unlink if file.respond_to?(:unlink)
        $files.delete id
      end
    end
  end

  # Fancy adapter for fanfiction.net's URLs
  get '/s/:id/?:ch?/?:title?/?' do
    style = ['light', 'dark'].sample
    query = URI.encode_www_form([[:style, style],
                                 [:url, "https://fanfiction.net/s/#{params[:id]}"]])
    redirect to("/get?#{query}")
  end

  # 404 Page
  not_found do
    status 404
    html = render 'errors/404'
    [true, false].sample ? html.gsub!(*replacements) : html
  end

  # 500 Page
  error Exception do
    status 500
    html = render 'errors/500'
    [true, false].sample ? html.gsub!(*replacements) : html
  end
end
