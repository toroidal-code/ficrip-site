workers 0 # Single mode
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 8)
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'
