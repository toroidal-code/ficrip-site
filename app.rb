require 'sinatra/base'
require 'newrelic_rpm'
require 'padrino-helpers'
require 'rufus-scheduler'
require 'concurrent'

require 'haml'
require 'slim'
require 'oj_mimic_json'
require 'ficrip'

$files = Concurrent::Map.new

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
if $scheduler_thread
  scheduler = Rufus::Scheduler.new
  scheduler.every '2h' do
    cleanup_old_files
  end
end


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

  replacements = [/(white|black|waves-light|light|dark)/,
                  { 'white'       => 'black', 'black' => 'white',
                    'light'       => 'dark', 'dark' => 'light',
                    'waves-light' => '' }]

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

  # Get a fanfic
  get '/get' do
    halt 403, render('errors/403') unless params[:url]
    html = render 'download', layout: :main
    params[:style] == 'dark' ? html.gsub(*replacements) : html
  end

  storyid_regexp = Regexp.new('fanfiction.net/s/(\d+)', true)

  # The real guts of the fetcher
  get '/generate', provides: 'text/event-stream' do
    id = params[:clientId]
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
        out << SSE.event(:info, {
            title: link_to(fic.title, fic.url),
            author: link_to(fic.author, fic.author_url)
        }.to_json)

        fetched = 0

        epub = fic.bind(version: 2, callback: lambda { # |fetched|
          fetched += 1
          percent = ((fetched / fic.chapters.count.to_f) * 100).to_i
          out << SSE.event(:progress, "#{percent}%")
          sleep 0.5 # poor man's rate limiter
        }).tap { |e| e.cleanup }

        # Switch to indeterminate
        out << SSE.event(:progress, "null")

        filename = "#{fic.author} - #{fic.title}.epub"

        temp = Tempfile.new(filename)
        epub.generate_epub_stream.tap do |es|
          es.rewind
          temp.write es.read
          es.close
        end

        $files[id] = Concurrent::Hash[filename: filename, tempfile: temp, time: Time.now]
        puts $files[id]
        out << SSE.event(:progress, "100%")
        out << SSE.event(:url, "/file/#{id}")
      rescue Exception => ex
        puts "An error of type #{ex.class} happened, message is #{ex.message}"
      end if fic

      out << SSE.event(:close, true)
    end
  end

    # Download the generated file
  get '/file/:id' do |id|
    file = $files[id]
    halt 404, render('errors/404') unless file
    begin
      #File.read(file[:tempfile].path)
      send_file file[:tempfile].path, filename: file[:filename], type: 'application/epub+zip', disposition: 'attachement'
    ensure
      file[:tempfile].close
      $files.delete id
    end
  end

  not_found do
    status 404
    html = render 'errors/404'
    [true, false].sample ? html.gsub!(*replacements) : html
  end

  error Exception do
    status 500
    html = render 'errors/500'
    [true, false].sample ? html.gsub!(*replacements) : html
  end
end
