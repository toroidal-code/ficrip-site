# frozen_string_literal: true
# Core
require 'sinatra/base'
require 'ficrip'

# Helpers
require 'active_support/dependencies/autoload'
require 'active_support/number_helper'
require 'padrino-helpers'
require 'slim'

# Concurrent
require 'concurrent/atomic/atomic_fixnum'
require 'concurrent/array'
require 'concurrent/map'

# Extras
require 'sinatra/asset_pipeline'
require 'rufus-scheduler'
require 'oj_mimic_json'
require 'retryable'
require 'uglifier'
require 'sass'

# Stdlib
require 'open-uri'

require_relative 'lib/event_receiver'

# Global settings
Slim::Engine.disable_option_validator!

# Constants
FANFICTION_STORY_REGEX_STRING = "^(https?://)?(www.)?fanfiction.net/s/\\d+(?!\\w)(/.*)?$|^\\d+$"
FANFICTION_STORY_REGEX = %r{ fanfiction.net/s/(\d+)(?!\w+)(/.*)?$ | ^(\d+)$ }i
DEFAULT_ERROR_MESSAGES = {
    400 => ['garbage in, garbage out'],
    403 => ['nope', '(nice try, though)'],
    404 => ['whoops'],
    406 => ['This... is... UNACCEPTABLE!!!',
            'Dungeon. Seven years dungeon, no trial.'],
    409 => ['CONFLICT!', 'I live for it'],
    410 => ['See, we <em>used</em> to have that...'],
    423 => ["Locked 'n loaded", '...ever hear of resource starvation?'],
    424 => ['Something else failed... then we failed',
            "So everybody fails. It's just one big ball of fail."],
    429 => ["Ever hear that saying about 'too much of a good thing'?",
            'Yeah. Well, that happened. Try again later-ish?'],
    500 => ['damn.', 'well, we tried'],
    505 => ['...what?']
}.freeze

# Global variables
$files = Concurrent::Map.new       # { 'uuid' => #File, 'uuid' => #Tempfile}
$to_delete = Concurrent::Array.new # ['uuid', ...]
$download_size = Concurrent::AtomicFixnum.new
$download_count = Concurrent::AtomicFixnum.new

# Cleanup tempfiles by checking to see
# if they're older than an hour
def cleanup_old_files
  # make a local copy of to_delete while simultaneously clearing the original (atomicity)
  # local_to_delete = $to_delete.slice!(0..-1).to_a
  local_to_delete = []
  $to_delete.delete_if { |v| local_to_delete << v; true }

  $files.each_pair do |uuid, file|
    if file.nil?
      $files.delete uuid
    elsif local_to_delete.include?(uuid) || (Time.now - 60*60) > file.ctime
      file.close                               # Close it
      file.unlink if file.respond_to? :unlink  # Unlink it if we can
      $files.delete uuid
    end
  end
  GC.start
end

# Every twenty minutes, clean up the leftover
# tempfiles that haven't already been GC'ed
Rufus::Scheduler.s.every('2m') { cleanup_old_files }

class Object
  def randomly
    [true, false].sample ? yield(self) : self
  end

  def with
    yield self
  end
end

# The core of the web application
# noinspection ALL
class Application < Sinatra::Base
  register Padrino::Helpers

  configure do
    enable :sessions
    enable :protection
    set session_secret: SecureRandom.hex(32)
    set protect_from_csrf: true # enable authenticity_token in forms
    set server: :puma
    use Rack::Protection, except: :http_origin
    set padrino_ath: Class.new { include Padrino::Helpers::AssetTagHelpers }.new
    set sprockets: (Sprockets::Environment.new(root) { |env| env.logger = Logger.new(STDOUT) })
    set assets_precompile: %w(app.js app.css *.js *.eot *.ttf *.woff *.woff2)
    sprockets.append_path File.join(root, 'assets', 'javascripts')
    sprockets.append_path File.join(root, 'assets', 'stylesheets')
    sprockets.append_path File.join(root, 'vendor', 'assets', 'javascripts')
    sprockets.append_path File.join(root, 'vendor', 'assets', 'stylesheets')
    sprockets.append_path File.join(root, 'vendor', 'assets', 'fonts')

    set assets_js_compressor: :uglifier
    set assets_css_compressor: :sass

    use Rack::Protection, except: :http_origin
    register Sinatra::AssetPipeline
    settings.sprockets.cache =
      if development?
        Sprockets::Cache::MemoryStore.new 1000
      else
        Sprockets::Cache::FileStore.new './tmp'
      end

    Ficrip.set_solverr(8191)
  end

  # The source-to-source transformations to switch themes
  switch_themes = lambda do |page|
    page.gsub(/(white|black|waves-light|light|dark)/,
              'white'       => 'black', 'black' => 'white',
              'light'       => 'dark', 'dark' => 'light',
              'waves-light' => '')
  end

  define_method(:switch_themes, &switch_themes)

  # Super fancy error handler
  def magic_error(code_or_msg = nil, code_or_msg2 = nil,
                  code: nil, msg: nil, generic: false, halt: true)
    [code_or_msg2, code_or_msg].each do |v|
      if v.is_a? Array
        msg = v
      elsif v.is_a? String
        msg = [v]
      elsif v.is_a? Integer
        code = v
      end
    end

    locals = Hash.new.tap do |h|
      unless code.nil?
        h[:code] = code unless generic
        h[:message] = DEFAULT_ERROR_MESSAGES[code]
      end
      h[:message] = msg unless msg.nil?
      h[:generic] = generic
    end

    if (code.nil? || generic)
      status 200
    else
      status code
    end

    page = render(:error, locals: locals).randomly { |p| switch_themes p }
    halt && !code.nil? ? halt(code, page) : page
  end

  # The index page
  ['/', '/simple/?'].each do |path|
    get(path) do
      render('simple', layout: :main).randomly(&switch_themes)
    end
  end

  # Advanced options
  get '/advanced/?' do
    render('advanced', layout: :main).randomly(&switch_themes)
  end

  # Light theme
  get '/light/?' do
    render 'simple', layout: :main
  end

  # Dark theme
  get '/dark/?' do
    render('simple', layout: :main).with(&switch_themes)
  end

  # About page
  get '/about/?' do
    render('about').randomly(&switch_themes)
  end

  # Get a fanfic via post. Basically the same as get, but with file uploading
  # Takes two query params: 'style' and 'url'
  # 'url' is, obviously, the fanfiction.net story's URL
  post '/get' do
    magic_error 400 unless params[:story]

    # Try to parse the StoryID
    unless (match = params[:story].match(FANFICTION_STORY_REGEX)).nil?
      begin
        Integer match.captures.reject(&:nil?).first
      rescue
        magic_error 400, ['garbage in, garbage out', '(your URL or ID is invalid)']
      end
    end

    # Write the uploaded data to a temporary file
    if params[:cover_file] && !params[:cover_file].empty?
      tempfile = Tempfile.new( params[:cover_file][:filename] ).tap do |temp|
        temp.write params[:cover_file][:tempfile].read
        temp.rewind
      end

      uuid = SecureRandom.uuid
      $files[uuid] = tempfile

      # Safety's sake since we're exposing params to the client through
      # string interpolation in the embedded javascript in the view
      params.delete 'cover_file' # keys are really strings? weird.
      params[:cover_uuid] = uuid
    end
    query = URI.encode_www_form params
    redirect "/get?#{query}"
  end

  get '/get' do
    magic_error 400 unless params[:story]

    # Try to parse the StoryID ...again
    unless (match = params[:story].match(FANFICTION_STORY_REGEX)).nil?
      begin
        Integer match.captures.reject(&:nil?).first
      rescue
        magic_error 400, ['garbage in, garbage out', '(your URL or ID is invalid)']
      end
    end

    html = render 'download', layout: :main
    (params[:style] || %w(light dark).sample) == 'dark' ? html.with(&switch_themes) : html
  end

  # The real guts of the fetcher
  get '/generate', provides: 'text/event-stream' do
    stream do |out| begin
      er = EventReceiver.new out
      Ficrip.solverr.open!

      # Get the cover
      cover = if params[:cover_uuid] && !params[:cover_uuid].empty?
        $files.get params[:cover_uuid]
      elsif params[:cover_url] && !params[:cover_url].empty?
        begin
          # Try to fetch the cover from the URL
          Retryable.retryable(tries: 5, on: OpenURI::HTTPError) { open(params[:cover_url]) }
        rescue OpenURI::HTTPError
          er.fire_event :error, magic_error("Couldn't fetch the cover at #{params[:cover_url]}.")
          next # Close the stream and halt
        rescue
          er.fire_event :error, magic_error("There's no cover at #{params[:cover_url]}.")
          next
        end
      end

      # Attempt to load the story
      fic = begin
        Ficrip.fetch params[:story]
      rescue ArgumentError
        # If we get an ArgumentError from the fetcher, then it's an invalid ID
        er.fire_event :error, magic_error("There's no fic with storyid #{params[:story]}.")
        next
      rescue => e
        # Otherwise, something else went wrong
        er.fire_event :error, magic_error(500, halt: false)
        p e and next
      end

      # Update the download page with title/author information
      er.fire_event :info, { title:  link_to(fic.title, fic.url, target: '_blank'),
                             author: link_to(fic.author, fic.author_url.to_s, target: '_blank') }.to_json

      epub_version = Integer params[:epub_version] rescue 2
      epub_version = 2 unless [2,3].include? epub_version

      # Process the story into an EPUB2, incrementing the progressbar
      epub = fic.bind version: epub_version , cover: cover, callback: -> (fetched, total) do
        percent = (fetched / total.to_f) * 100
        er.fire_event :progress, "#{percent.to_i}%"
        sleep 0.1 # poor man's rate limiter
      end

      filename = "#{fic.author} - #{fic.title}.epub"

      temp = Tempfile.new filename  # Create temporary file
      temp.singleton_class.class_eval { attr_reader :filename }
      temp.instance_variable_set :@filename, filename

      # Write the epub to the tempfile
      epub.generate_epub_stream.tap do |es|
        es.rewind          # Rewind
        temp.write es.read # Copy
        es.close           # Close
        temp.flush         # Flush
      end

      # Only mark the cover for deletion once we've written the epub to disk
      $to_delete << params[:cover_uuid] if params[:cover_uuid] && !params[:cover_uuid].empty?

      # Store the tempfile into the hash
      file_uuid = SecureRandom.uuid
      $files[file_uuid] = temp

      # Encode the file information into a query string
      query = URI.encode_www_form(uuid: file_uuid)

      er.fire_event :backbutton
      er.fire_event :progress, '100%'       # We're done, so set progress to 100%
      er.fire_event :url, "/file?#{query}"  # And give the client the file link
    ensure
      Ficrip.solverr.close!
      er.fire_event :close                  # Close the EventSource
      out.close
    end; end
  end

  # Download the generated file
  get '/file' do
    magic_error 403 unless params[:uuid]
    file = $files.get params[:uuid]
    magic_error 404 unless file && File.file?(file.path)

    # Statistics
    $download_count.increment
    $download_size.increment File.size(file.path)

    $to_delete << params[:uuid] # Add the uuid to our list of files to cleanup
    send_file file.path, filename: file.filename, type: 'application/epub+zip'
  end

  # Fancy adapter for fanfiction.net's URLs
  get '/s/:storyid/?:ch?/?:title?/?' do
    query = URI.encode_www_form(story: params[:storyid])
    redirect "/get?#{query}", 307
  end

  get '/stats' do
    render('stats').randomly(&switch_themes)
  end

  get '/stats.json', provides: ['text/html', 'text/json'] do
    Hash[downloads: { size:  $download_size.value,
                      count: $download_count.value }].to_json
  end

  # Error pages, because why not.
  get '/errors/:id' do
    code = Integer params[:id] rescue not_found

    if DEFAULT_ERROR_MESSAGES.include? code
      # Modify the existing status code in the response
      catch(:halt) { magic_error code }.tap { |r| r[0] = 200 }
    else
      not_found
    end
  end

  # 404 Page
  not_found do
    magic_error 404
  end

  # 500 Page
  error Exception do
    magic_error 500
  end
end
