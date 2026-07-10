# Accumulates streamed LLM deltas and answers "is it time to flush?" on a
# time/size cadence. Pure value object — it never broadcasts and never clears
# its text (each flush re-renders the FULL accumulated buffer). The clock is
# injectable so tests drive timing without sleeping.
class Message::StreamBuffer
  def initialize(interval: ENV.fetch("STREAM_FLUSH_INTERVAL_MS", 150).to_i / 1000.0,
                 max_bytes: ENV.fetch("STREAM_FLUSH_MAX_BYTES", 4096).to_i,
                 clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @interval   = interval
    @max_bytes  = max_bytes
    @clock      = clock
    @text       = +""
    @last_flush = @clock.call
  end

  def <<(delta)
    @text << delta
    self
  end

  # True when the interval has elapsed or the buffer hit the size cap.
  # Resets the flush timer; the buffer text is never cleared (full re-render).
  def flush?
    return false if @text.empty?
    current = @clock.call
    due = current - @last_flush >= @interval || @text.bytesize >= @max_bytes
    @last_flush = current if due
    due
  end

  def text = @text.dup
  def any? = @text.present?
end