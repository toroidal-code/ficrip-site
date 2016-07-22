require 'sinatra/base'
require 'padrino-helpers'
require 'message_bus'
require 'rufus-scheduler'
require 'concurrent'

require 'haml'
require 'json'
require 'ficrip'

MessageBus.configure(backend: :memory)

$files    = Concurrent::Map.new
scheduler = Rufus::Scheduler.new

# Cleanup old files by checking to see
# if they're older than 6 hours
def cleanup_old_files
  to_delete = []
  $files.each_key do |id|
    if (Time.now - (6 * 60 * 60)) > $files[id][:time]
      $files[id][:tempfile].close
      $files[id][:tempfile].unlink
      to_delete << id
    end
  end
  to_delete.each { |k| $files.delete k }
rescue => e
  p e
end

# Every two hours, clean up the leftover tempfiles that
# haven't already been GC'ed
scheduler.every '2h' do
  cleanup_old_files
end

class Application < Sinatra::Base
  register Padrino::Helpers
  use MessageBus::Rack::Middleware

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

  replacements = [/(white|black|waves-light|light|dark)/,
                  { 'white'       => 'black', 'black' => 'white',
                    'light'       => 'dark', 'dark' => 'light',
                    'waves-light' => '' }]

  get '/' do
    html = render 'index'
    html.gsub!(*replacements) if [true, false].sample
    html
  end

  # Light theme
  get '/light' do
    render 'index'
  end

  # Dark theme
  get '/dark' do
    render('index').gsub(*replacements)
  end

  # Get a fanfic
  get '/get' do
    html = render 'download'
    html.gsub!(*replacements) if params[:style] == 'dark'
    html
  end

  storyid_regexp = Regexp.new('fanfiction.net/s/(\d+)', true)

  # The real guts of the fetcher
  post '/get' do
    id  = params[:id]
    url = params[:url]

    storyid = begin
      Integer url.match(storyid_regexp)[1]
    rescue
      MessageBus.publish '/progress', { id: id, message: "Error! \"#{url}\" isn't a valid story URL." }
    end

    fic = begin
      Ficrip.fetch storyid
    rescue
      MessageBus.publish '/progress', { id: id, message: "Error! There is no fic with id #{storyid}." }
    end if storyid

    begin
      fetched = 0

      epub = fic.bind(version: 2, callback: lambda {
        fetched += 1
        percent = ((fetched / fic.chapters.count.to_f) * 100).to_i
        MessageBus.publish '/progress', { id: id, progress: "#{percent}%" }
        sleep 1 # poor man's rate limiter
      })

      # Switch to indeterminate
      MessageBus.publish '/progress', { id: id, progress: nil }

      filename = "#{fic.author} - #{fic.title}.epub"

      temp = Tempfile.new(filename)

      epub.cleanup
      Zip::OutputStream::write_buffer(temp) { |f| epub.write_to_epub_container f }

      $files[id] = Concurrent::Hash[filename: filename, tempfile: temp, time: Time.now]
      MessageBus.publish '/progress', { id: id, url: "/file/#{id}" }
    rescue Exception => ex
      puts "An error of type #{ex.class} happened, message is #{ex.message}"
    end if fic
    'OK'
  end

  # Download the generated file
  get '/file/:id' do |id|
    file = $files[id]
    begin
      send_file file[:tempfile].path, filename: file[:filename], type: 'application/epub+zip'
    ensure
      file[:tempfile].close
      MessageBus.publish '/progress', { id: id, url: '/' }
    end
  end

  not_found do
    status 404
    html = render 'errors/404', layout: :error
    html.gsub!(*replacements) if [true, false].sample
    html
  end

  error Exception do
    status 500
    html = render 'errors/500', layout: :error
    html.gsub!(*replacements) if [true, false].sample
    html
  end
end