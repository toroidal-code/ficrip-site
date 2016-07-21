require 'sinatra/base'
require 'padrino-helpers'
require 'haml'

class Application < Sinatra::Base
  register Padrino::Helpers

  configure do
    enable :sessions
    set :session_secret, SecureRandom.hex(32)
    # enable authenticity_token in forms
    set :protect_from_csrf, true
    # actual checks for csrf tokens from form submissions
    use Rack::Protection::AuthenticityToken
  end

  replacements = [/(white|black|waves-light)/, { 'white' => 'black', 'black' => 'white', 'waves-light' => '' }]

  get '/' do
    html = render 'index'
    html.gsub!(*replacements) if [true, false].sample
    html
  end

  get '/light' do
    render 'index'
  end

  get '/dark' do
    render('index').gsub(*replacements)
  end
end