# This is a simple little helper
# class for properly formatting
# Server-Sent Event messages
class EventReceiver
  attr_reader :stream

  # Start with the event stream
  def initialize(stream)
    @stream = stream
  end

  # Set the event name buffer to ev and maybe send data
  def event(ev, obj = nil)
    @stream << "event: #{ev}\n"
    data(obj) unless obj.nil?
    self
  end

  # Append obj to the data buffer
  def data(obj)
    @stream << "data: #{obj}\n"
    self
  end

  # Set the event stream's last event ID
  def id(val)
    @stream << "id: #{val}\n"
    self
  end

  # Set the event stream's reconnection time
  def retry(num)
    @stream << "retry: #{num}\n"
    self
  end

  # Dispatch the event
  def fire!
    @stream << "\n"
    self
  end

  # Construct an event and dispatch it
  def fire_event(ev, obj = true)
    event(ev, obj).fire!
  end

  # Construct a message and dispatch it
  def send_message(*args)
    data(*args).fire!
  end
end
