require 'sinatra/base'
require 'newrelic_rpm'
require 'padrino-helpers'
require 'rufus-scheduler'
require 'concurrent/map'
require 'concurrent/array'

require 'slim'
require 'oj_mimic_json'
require 'ficrip'

require 'open-uri'

FANFICTION_STORY_REGEX_STRING = "^(https?://)?(www.)?fanfiction.net/s/\\d+(?!\\w)(/.*)?$|^\\d+$"
FANFICTION_STORY_REGEX = Regexp.compile('fanfiction.net/s/(\d+)(?!\w+)(/.*)?$|^(\d+)$',true)

$files = Concurrent::Map.new
$to_delete = Concurrent::Array.new

# Cleanup tempfiles by checking to see
# if they're older than an hour
def cleanup_old_files
  $files.each_key do |uuid|
    if $to_delete.include?(uuid) || (Time.now - (60 * 60)) > $files[uuid][:time]
      $files[uuid][:tempfile].close
      $files[uuid][:tempfile].unlink if $files[uuid].respond_to?(:unlink)
      $to_delete.delete uuid
      $files.delete uuid
    end
  end
end

# Every thirty minutes, clean up the leftover tempfiles that
# haven't already been GC'ed
if $scheduler_thread
  scheduler = Rufus::Scheduler.new
  scheduler.every '30m' do
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

    set server: :puma
  end

  # The source-to-source transformations to switch themes
  replacements = [/(white|black|waves-light|light|dark)/,
                  { 'white'       => 'black', 'black' => 'white',
                    'light'       => 'dark', 'dark' => 'light',
                    'waves-light' => '' }]

  # The index page
  ['/', '/simple/?'].each do |path|
    get path do
      html = render 'index', layout: :main
      [true, false].sample ? html.gsub(*replacements) : html
    end
  end

  get '/advanced/?' do
    html = render 'advanced', layout: :main
    [true, false].sample ? html.gsub(*replacements) : html
  end

  # Light theme
  get '/light/?' do
    render 'index', layout: :main
  end

  # Dark theme
  get '/dark/?' do
    render('index', layout: :main).gsub(*replacements)
  end

  get '/about/?' do
    html = render('about')
    (params[:style] || %w(light dark).sample) == 'dark' ? html.gsub(*replacements) : html
  end
  # Get a fanfic via post. Basically the same as get, but with file uploading
  # Takes two query params: 'style' and 'url'
  # 'url' is, obviously, the fanfiction.net story's URL
  post '/get' do
    halt 403, render('errors/403') unless params[:story]

    if params[:cover_file] && !params[:cover_file].empty? &&
        params[:cover_uuid] && !params[:cover_uuid].empty?

      tempfile = Tempfile.new(params[:cover_file][:filename]).tap do |temp|
        temp.write params[:cover_file][:tempfile].read
        temp.rewind
      end

      $files[params[:cover_uuid]] = {
          tempfile: tempfile,
          filename: params[:cover_file][:filename],
          time:     Time.now
      }
    end

    # Safety's sake since we're exposing params to the client through string interpolation
    # in the embedded javascript in the view
    params[:cover_file] = nil

    # Try to parse the StoryID
    unless (match = params[:story].match(FANFICTION_STORY_REGEX)).nil?
      match_item = match.captures.reject(&:nil?).first
      Integer match_item rescue
          halt 403, render(:error, locals: { message: "\"#{params[:story]}\" isn't a valid story URL or ID."})
    end

    html = render 'download', layout: :main
    (params[:style] || %w(light dark).sample) == 'dark' ? html.gsub(*replacements) : html
  end

  # The real guts of the fetcher
  get '/generate', provides: 'text/event-stream' do
    cover = if params[:cover_uuid]
              $files[params[:cover_uuid]][:tempfile]
            elsif params[:cover_url] && !params[:cover_url].empty?
              open(params[:cover_url])
            end

    stream do |out|
      # # Attempt to load the story
      fic = begin
        Ficrip.fetch params[:story]
      rescue ArgumentError
        # If we get an ArgumentError from the fetcher, then it's an invalid ID
        out << SSE.event(:error, render(:error, locals: { message: "There's no fic with storyid #{params[:story]}."}))
        out << SSE.event(:close, true) and next  # Close the connection
       rescue => e
        # Otherwise, something else went wrong
        out << SSE.event(:error, render('errors/500')) and p e
        out << SSE.event(:close, true) and next  # Close the connection
      end

      # Update the download page with title/author information
      out << SSE.event(:info, {
          title:  link_to(fic.title, fic.url),
          author: link_to(fic.author, fic.author_url)
      }.to_json)

      epub_version = params[:epub_version] ? params[:epub_version].to_i : 2

      # Process the story into an EPUB2, incrementing the progressbar
      epub = fic.bind version: epub_version, cover: cover, callback: lambda { |fetched, total|
        percent = (fetched / total.to_f) * 100
        out << SSE.event(:progress, "#{percent.to_i}%")
        sleep 0.5 # poor man's rate limiter
      }

      # Switch to the indeterminate progressbar
      out << SSE.event(:progress, 'null')

      filename = "#{fic.author} - #{fic.title}.epub"
      temp     = Tempfile.new filename  # Create temporary file

      # Write the epub to the tempfile
      epub.generate_epub_stream.tap do |es|
        es.rewind
        temp.write es.read
        es.close
      end

      # Store the tempfile into the hash
      $files[temp.path] = { tempfile: temp, time: Time.now }

      # Encode the file information into a query string
      query = URI.encode_www_form([[:filename, filename], [:path, temp.path]])

      out << SSE.event(:progress, '100%')      # We're done, so set progress to 100%
      out << SSE.event(:url, "/file?#{query}") # And give the client the file link

      out << SSE.event(:close, true)           # Close the EventSource
    end
  end

  # Download the generated file
  get '/file' do
    path, filename = params[:path], params[:filename]
    halt 403, render('errors/403') unless path && filename

    $to_delete << path # Add the path to our list of files to cleanup
    send_file path, filename: filename, type: 'application/epub+zip'
  end

  # Fancy adapter for fanfiction.net's URLs
  get '/s/:storyid/?:ch?/?:title?/?' do
    query = URI.encode_www_form([[:storyid, params[:storyid]]])
    redirect "/get?#{query}"
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
