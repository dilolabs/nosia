require "test_helper"

class Message::StreamBufferTest < ActiveSupport::TestCase
  FakeClock = Struct.new(:ticks) do
    def call = ticks.shift
  end

  def buffer(interval: 10, max_bytes: 4096, ticks:)
    Message::StreamBuffer.new(interval: interval, max_bytes: max_bytes, clock: FakeClock.new(ticks))
  end

  test "<< accumulates and text returns the full buffer" do
    b = buffer(ticks: [ 0.0 ])
    b << "hello "
    b << "world"
    assert_equal "hello world", b.text
    assert b.any?
  end

  test "flush? is false on an empty buffer" do
    b = buffer(ticks: [ 0.0, 1.0 ])
    assert_not b.flush?
  end

  test "flush? is false before the interval elapses" do
    b = buffer(interval: 10, ticks: [ 0.0, 1.0 ]) # 1.0 - 0.0 = 1s < 10s
    b << "a"
    assert_not b.flush?
  end

  test "flush? is true once the interval elapses and resets the timer" do
    b = buffer(interval: 10, ticks: [ 0.0, 10.0, 10.0 ])
    b << "a"
    assert b.flush?        # 10 - 0 = 10 >= 10
    assert_not b.flush?    # timer reset to 10.0; 10 - 10 = 0 < 10
  end

  test "flush? is true when max_bytes is reached before the interval" do
    b = buffer(interval: 1000, max_bytes: 5, ticks: [ 0.0, 1.0 ])
    b << "abcde"           # 5 bytes >= max_bytes
    assert b.flush?
  end

  test "flushing never clears the text (full re-render semantics)" do
    b = buffer(interval: 0, ticks: [ 0.0, 0.0 ])
    b << "a"
    b.flush?               # flushes (interval 0)
    b << "b"
    assert_equal "ab", b.text
  end
end